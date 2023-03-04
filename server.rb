require 'sinatra'
require 'sequel'
require 'byebug'
set :show_exceptions, false

DB = Sequel.connect('sqlite://test.db')
Dir["#{Dir.pwd}/models/*"].each {|file| require file }

error Sequel::NoMatchingRow do
  error_message = 'Передан неверный ID продукта'
  content_type :json
  status(404)
  return {
    message: error_message
  }.to_json
end

class WriteOffExceeded < Exception; end
class IncorrectUser < Exception; end

error WriteOffExceeded do
  error_message = 'Неверное количество баллов'
  content_type :json
  status(422)
  return {
    message: error_message
  }.to_json
end

error IncorrectUser do
  error_message = 'Передан неверный пользователь'
  content_type :json
  status(422)
  return {
    message: error_message
  }.to_json
end

post '/operation' do
  response = {}
  response[:positions] = []

  user = User.with_pk!(parameters[:user_id])
  positions = parameters[:positions]

  response[:user_information] = {
    name: user.name
  }

  positions.each do |position|
    product = Product.with_pk!(position[:id])
    attributes = product.values.except(:id)
    attributes[:price] = position[:price]

    if attributes[:type] == 'discount'
      attributes[:discount_percent] = attributes[:value].to_i
      attributes[:discount] =
        calculate_percent(attributes[:price], attributes[:value].to_i)
    else
      attributes[:discount_percent] = 0
      attributes[:discount] = 0
    end

    response[:positions] << attributes
  end

  user_discount = user.template.discount

  common_sum = 0
  common_discount_sum = 0

  positions.each do |position|
    product = Product.with_pk!(position[:id])
    position_sum = position[:price] * position[:quantity]
    common_sum += position_sum
    next unless product.type == 'discount'

    common_discount_sum += calculate_percent(position_sum, product.value.to_i)
  end

  common_discount_sum += calculate_percent(common_sum, user_discount)
  common_discount_percent = common_discount_sum.to_f / common_sum * 100

  response[:common_discount] = {
    common_discount_percent:,
    common_discount_sum:
  }

  user_cashback = user.template.cashback

  available_bonuses_balance =
    user.bonus - user.operations_dataset.where(done: nil).sum(:allowed_write_off)
  common_cashback_sum = 0

  positions.each do |position|
    product = Product.with_pk!(position[:id])
    next unless product.type == 'increased_cashback'

    position_sum = position[:price] * position[:quantity]
    common_cashback_sum += calculate_percent(position_sum, product.value.to_i)
  end

  check_summ = common_sum - common_discount_sum
  response[:check_summ] = check_summ

  if user.template.name != 'Gold'
    sum_of_noloyalty_product = 0

    positions.each do |position|
      product = Product.with_pk!(position[:id])
      next unless product.type == 'noloyalty'

      position_sum = position[:price] * position[:quantity]
      sum_of_noloyalty_product += position_sum
    end
    common_cashback_sum +=
      calculate_percent(check_summ - sum_of_noloyalty_product, user_cashback)
  end

  common_cashback_percent = common_cashback_sum.to_f / check_summ * 100

  response[:bonuses] = {
    user_balance: user.bonus,
    available_bonuses_balance:,
    common_cashback_percent:,
    common_cashback_sum:
  }

  allowed_write_off = 0

  positions.each do |position|
    product = Product.with_pk!(position[:id])
    next if product.type == 'noloyalty'

    position_sum = position[:price] * position[:quantity]
    allowed_write_off += position_sum
  end

  operation_params = {
    user_id: user.id,
    cashback: common_cashback_sum,
    cashback_percent: common_cashback_percent,
    discount: common_discount_sum,
    discount_percent: common_discount_percent,
    check_summ:,
    allowed_write_off:
  }

  operation = create_operation(**operation_params)

  response[:operation_id] = operation.id

  content_type :json
  response.to_json
end

post '/submit' do
  operation = Operation.with_pk!(parameters[:operation_id])

  raise IncorrectUser if operation.user_id != parameters[:user][:id]
  raise WriteOffExceeded if operation.allowed_write_off < parameters[:write_off]

  response = {}


  write_off = parameters[:write_off]
  check_summ = operation.check_summ - write_off
  cashback = check_summ * operation.cashback_percent

  operation.update(
    done: true,
    cashback:,
    check_summ:,
    write_off:
  )

  response[:operation] = operation.values.except(:id)

  content_type :json
  response.to_json
end

def create_operation(**kwargs)
  Operation.create(**kwargs)
end


def calculate_percent(sum, percent)
  sum.to_f * percent / 100
end

def parameters
  @parameters ||= JSON.parse(request.body.read, symbolize_names: true)
end
