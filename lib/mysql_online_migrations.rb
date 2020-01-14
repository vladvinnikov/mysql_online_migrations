require 'active_record'
require "active_record/migration"
require "active_record/connection_adapters/mysql2_adapter"

%w(*.rb).each do |path|
  Dir["#{File.dirname(__FILE__)}/mysql_online_migrations/#{path}"].each { |f| require(f) }
end

module MysqlOnlineMigrations

  class << self; attr_accessor :verbose; end

  def self.prepended(base)
    ActiveRecord::Base.send(:class_attribute, :mysql_online_migrations, :instance_writer => false)
    ActiveRecord::Base.send("mysql_online_migrations=", true)
  end

  def connection
    original_connection = super
    adapter_mode = original_connection.class.name == "ActiveRecord::ConnectionAdapters::Mysql2Adapter"
    makara_mode  = original_connection.class.name == "ActiveRecord::ConnectionAdapters::MakaraMysql2Adapter"

    @original_adapter ||= if adapter_mode
      original_connection
    elsif makara_mode
      original_connection.instance_variable_get(:@master_pool)
                         .instance_variable_get(:@connections)
                         .first
                         .instance_variable_get(:@connection)
    else
      original_connection.instance_variable_get(:@delegate)
    end

    @no_lock_adapter ||= ActiveRecord::ConnectionAdapters::Mysql2AdapterWithoutLock.new(@original_adapter, MysqlOnlineMigrations.verbose)

    if adapter_mode
      @no_lock_adapter
    elsif makara_mode
      master_pool = original_connection.instance_variable_get(:@master_pool)
      connection  = master_pool.instance_variable_get(:@connections).first
      connection.instance_variable_set(:@connection, @no_lock_adapter)
      master_pool.instance_variable_set(:@connections, [connection])
      original_connection.instance_variable_set(:@master_pool, master_pool)
      original_connection
    else
      original_connection.instance_variable_set(:@delegate, @no_lock_adapter)
      original_connection
    end
  end

  def with_lock(&blk)
    with_enabled_online_migrations(false, &blk)
  end

  def without_lock(&blk)
    with_enabled_online_migrations(true, &blk)
  end

  private

  def with_enabled_online_migrations(enabled)
    original_value = ActiveRecord::Base.mysql_online_migrations
    ActiveRecord::Base.mysql_online_migrations = enabled
    yield
    ActiveRecord::Base.mysql_online_migrations = original_value
  end
end

ActiveRecord::Migration.send(:prepend, MysqlOnlineMigrations)