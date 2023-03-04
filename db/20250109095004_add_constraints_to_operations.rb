Sequel.migration do
  class Operation < Sequel::Model; end

  change do
    Operation.where(allowed_write_off: nil).all.each do |operation|
      operation.update(allowed_write_off: 0)
    end

    alter_table(:operations) do
      set_column_not_null :allowed_write_off
      set_column_default :allowed_write_off, 0
    end
  end
end
