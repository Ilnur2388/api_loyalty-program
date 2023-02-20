require 'sinatra'

db = SQLite3::Database.new "test.db"


get '/' do
  'Put this in your pipe & smoke it!'
end