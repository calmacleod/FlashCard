require "sqlite_vec"

module SqliteVecExtension
  def configure_connection
    super
    db = raw_connection
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(SqliteVecExtension)
end
