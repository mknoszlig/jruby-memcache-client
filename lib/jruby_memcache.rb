require 'java'
require File.dirname(__FILE__) + '/java_memcached-release_2.0.1.jar'

class JMemCache
  include_class 'com.danga.MemCached.MemCachedClient'
  include_class 'com.danga.MemCached.SockIOPool'
    
  VERSION = '1.5.0'

  ##
  # Default options for the cache object.

  DEFAULT_OPTIONS = {
    :namespace   => nil,
    :readonly    => false,
    :multithread => true,
    :pool_initial_size => 5,
    :pool_min_size => 5,
    :pool_max_size => 250,
    :pool_max_idle => (1000 * 60 * 60 * 6),
    :pool_maintenance_thread_sleep => 30,
    :pool_use_nagle => false,
    :pool_socket_timeout => 3000,
    :pool_socket_connect_timeout => 3000
  }

  ##
  # Default memcached port.

  DEFAULT_PORT = 11211

  ##
  # Default memcached server weight.

  DEFAULT_WEIGHT = 1
  
  attr_accessor :request_timeout

  ##
  # The namespace for this instance

  attr_reader :namespace

  ##
  # The multithread setting for this instance

  attr_reader :multithread

  ##
  # The servers this client talks to.  Play at your own peril.

  attr_reader :servers
  
  def initialize(*args)
    @servers = []
    opts = {}

    case args.length
    when 0 then # NOP
    when 1 then
      arg = args.shift
      case arg
      when Hash   then opts = arg
      when Array  then @servers = arg
      when String then @servers = [arg]
      else raise ArgumentError, 'first argument must be Array, Hash or String'
      end
    when 2 then
      @servers, opts = args
    else
      raise ArgumentError, "wrong number of arguments (#{args.length} for 2)"
    end

    opts = DEFAULT_OPTIONS.merge opts
        
    @namespace   = opts[:namespace]

    @client = MemCachedClient.new
    
    @client.primitiveAsString = true 
  	@client.sanitizeKeys = false 
  	
    weights = Array.new(@servers.size, DEFAULT_WEIGHT)

		@pool = SockIOPool.getInstance

    # // set the servers and the weights
    @pool.servers = @servers.to_java(:string)
    @pool.weights = weights.to_java(:Integer)
        
    # // set some basic pool settings
    # // 5 initial, 5 min, and 250 max conns
    # // and set the max idle time for a conn
    # // to 6 hours
    @pool.initConn = opts[:pool_initial_size]
    @pool.minConn = opts[:pool_min_size] 
    @pool.maxConn = opts[:pool_max_size]
    @pool.maxIdle = opts[:pool_max_idle]

    # // set the sleep for the maint thread
    # // it will wake up every x seconds and
    # // maintain the pool size
    @pool.maintSleep = opts[:pool_maintenance_thread_sleep]
    # 
    # // set some TCP settings
    # // disable nagle
    # // set the read timeout to 3 secs
    # // and don't set a connect timeout
    @pool.nagle = opts[:pool_use_nagle]
    @pool.socketTO = opts[:pool_socket_timeout]
    @pool.socketConnectTO = opts[:pool_socket_connect_timeout]
    @pool.aliveCheck = true
    @pool.initialize__method
		
  end
  
  def alive?
    @pool.servers.to_a.any?
  end

  def get(key, raw = false)
    value = @client.get(make_cache_key(key))
    return nil if value.nil?
    
    value = Marshal.load value unless raw
    value
  end
  
  def set(key, value, expiry = 0, raw = false)
    value = Marshal.dump value unless raw
    key = make_cache_key(key)
    if expiry == 0
      @client.set key, value
    else
      expiration_date = java.util.Date.new((Time.now.to_i + expiry) * 1000)
      @client.set key, value, expiration_date
    end
  end
  
  def add(key, value, expiry = 0, raw = false)
    @client.add(make_cache_key(key), value)
  end
  
  def delete(key, expiry = 0)
    @client.delete(make_cache_key(key))
  end
  
  def incr(key, amount = 1)
    @client.incr(make_cache_key(key), amount)
  end
  
  def decr(key, amount = 1)
    @client.decr(make_cache_key(key), amount)
  end
  
  def []=(key, value)
    set key, value
  end
    
  def flush_all
    @client.flushAll
  end
  
  def stats
    stats_hash = {}
    @client.stats.each do |server, stats|
      stats_hash[server] = Hash.new
      stats.each do |key, value|
        unless key == 'version'
          value = value.to_f
          value = value.to_i if value == value.ceil
        end
        stats_hash[server][key] = value
      end
    end
    stats_hash
  end
    
  protected
  
  def make_cache_key(key)
    if namespace.nil? then
      key
    else
      "#{@namespace}:#{key}"
    end
  end
  
  class MemCacheError < RuntimeError; end
  
end

