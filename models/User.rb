class User < Sequel::Model
  one_to_many :operations
  many_to_one :template
end
