class Operation < Sequel::Model
  many_to_one :user
end
