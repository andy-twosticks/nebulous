require 'stomp'
require 'json'
require 'time'

module NebulousStomp


  ##
  # A Class to deal with talking to STOMP via the Stomp gem.
  #
  # You will need to instantiate this yourself if you only want to listen for messages. But if you
  # want to send a request and receive a response, you should never need this -- a NebRequest
  # returns a Message.
  #
  class StompHandler

    attr_reader :client


    ##
    # Class methods
    #
    class << self


      ##
      # Parse stomp headers & body and return body as something Ruby-ish.
      # It might not be a hash, in fact -- it could be an array of hashes.
      #
      # We assume that you are getting this from a STOMP message; the routine
      # might not work if it is passed something other than Stomp::Message
      # headers.  
      #
      # If you have better intelligence as to the content type of the message,
      # pass the content type as the optional third parameter.
      #
      def body_to_hash(headers, body, contentType=nil)
        hdrs = headers || {}

        raise ArgumentError, "headers is not a hash" unless hdrs.kind_of? Hash

        type = contentType \
               || hdrs["content-type"] || hdrs[:content_type] \
               || hdrs["contentType"]  || hdrs[:contentType]

        hash = nil

        if type =~ /json$/i 
          begin
            hash = JSON.parse(body)
          rescue JSON::ParserError, TypeError
            hash = {}
          end

        else
          # We assume that text looks like STOMP headers, or nothing
          hash = {}
          body.to_s.split("\n").each do |line|
            k,v = line.split(':', 2).each{|x| x.strip! }
            hash[k] = v
          end

        end

        hash
      end


      ##
      # :call-seq:
      #   StompHandler.with_timeout(secs) -> (nil)
      #
      # Run a routine with a timeout.
      #
      # Example:
      #  StompHandler.with_timeout(10) do |r|
      #    sleep 20
      #    r.signal
      #  end
      #
      # Use `r.signal` to signal when the process has finished. You need to
      # arrange your own method of working out whether the timeout fired or not.
      #
      # Also, please note that when the timeout period expires, your code will
      # keep running. The timeout will only be honoured when your block
      # completes. This is very useful for Stomp.subscribe, but probably not
      # for anything else...
      #
      # There is a Ruby standard library for this, Timeout. But there appears to
      # be some argument as to whether it is threadsafe; so, we roll our own. It
      # probably doesn't matter since both Redis and Stomp do use Timeout. But.
      #
      def with_timeout(secs)
        mutex    = Mutex.new
        resource = ConditionVariable.new

        t = Thread.new do
          mutex.synchronize { yield resource }
        end

        mutex.synchronize { resource.wait(mutex, secs) }

        nil
      end

    end
    ##


    ##
    # Initialise StompHandler by passing the parameter hash.
    #
    # If no hash is set we try and get it from NebulousStomp::Param.
    # ONLY set testClient when testing.
    #
    def initialize(connectHash=nil, testClient=nil)
      @stomp_hash   = connectHash ? connectHash.dup : nil
      @stomp_hash ||= Param.get(:stompConnectHash)

      @test_client = testClient
      @client      = nil
    end


    ##
    # Connect to the STOMP client.
    #
    def stomp_connect
      return self unless nebulous_on?
      NebulousStomp.logger.info(__FILE__) {"Connecting to STOMP"} 

      @client = @test_client || Stomp::Client.new( @stomp_hash )
      raise ConnectionError, "Stomp Connection failed" unless connected?

      conn = @client.connection_frame()
      if conn.command == Stomp::CMD_ERROR
        raise ConnectionError, "Connect Error: #{conn.body}"
      end

      self

    rescue => err
      raise ConnectionError, err
    end


    ##
    # Drop the connection to the STOMP Client
    #
    def stomp_disconnect
      if @client
        NebulousStomp.logger.info(__FILE__) {"STOMP Disconnect"}
        @client.close if @client
        @client = nil
      end

      self
    end


    ##
    # return true if we are connected to the STOMP server
    #
    def connected?
      @client && @client.open?
    end


    ##
    # return true if Nebulous is turned on in the parameters
    #
    def nebulous_on?
      @stomp_hash && !@stomp_hash.empty?
    end


    ##
    # Block for incoming messages on a queue.  Yield each message.
    #
    # Note that the blocking happens in a thread somewhere inside the STOMP
    # client. I have no idea how to join that, and if the examples on the STOMP
    # gem are to be believed, you flat out can't -- the examples just have the
    # main thread sleeping so that it does not termimate while the thread is
    # running.  So to use this make sure that you at some point do something
    # like:
    #     loop; sleep 5; end
    #
    def listen(queue)
      return unless nebulous_on?
      NebulousStomp.logger.info(__FILE__) {"Subscribing to #{queue}"}

      stomp_connect unless @client

      # Startle the queue into existence. You can't subscribe to a queue that
      # does not exist, BUT, you can create a queue by posting to it...
      @client.publish( queue, "boo" )

      @client.subscribe( queue, {ack: "client-individual"} ) do |msg|
        begin
          @client.ack(msg)
          yield Message.from_stomp(msg) unless msg.body == 'boo'
        rescue =>e
          NebulousStomp.logger.error(__FILE__) {"Error during polling: #{e}" }
        end
      end

    end


    ##
    # As listen() but give up after yielding a single message, and only wait
    # for a set number of seconds before giving up anyway.
    #
    # The behaviour here is slightly different than listen(). If you return true from your block,
    # the message will be consumed and the method will end.  Otherwise it will continue until it
    # sees another message, or reaches the timeout.
    #
    # Put another way, since most things are truthy -- if you want to examine messages to find the
    # right one, return false from the block to get another.
    #
    def listen_with_timeout(queue, timeout)
      return unless nebulous_on?

      NebulousStomp.logger.info(__FILE__) do
        "Subscribing to #{queue} with timeout #{timeout}"
      end

      stomp_connect unless @client

      @client.publish( queue, "boo" )

      done = false

      StompHandler.with_timeout(timeout) do |resource|
        @client.subscribe( queue, {ack: "client-individual"} ) do |msg|

          begin
            if msg.body == "boo"
              @client.ack(msg)
            else
              done = yield Message.from_stomp(msg) 
              @client.ack(msg) if done
            end

          rescue =>e
            NebulousStomp.logger.error(__FILE__) {"Error during polling: #{e}" }
          end

          if done
            # Not that this seems to do any good when the Stomp gem is in play
            resource.signal 
            break
          end

        end # of Stomp client subscribe block

        resource.signal if done #or here. either, but.
      end # of with_timeout

      raise NebulousTimeout unless done
    end


    ##
    # Send a Message to a queue; return the message.
    #
    def send_message(queue, mess)
      return nil unless nebulous_on?
      raise NebulousStomp::NebulousError, "That's not a Message" \
        unless mess.respond_to?(:body_for_stomp) \
            && mess.respond_to?(:headers_for_stomp)

      stomp_connect unless @client

      headers = mess.headers_for_stomp.reject{|k,v| v.nil? || v == "" }
      @client.publish(queue, mess.body_for_stomp, headers)

      mess
    end


    ##
    # Return the neb-reply-id we're going to use for this connection
    #
    def calc_reply_id
      return nil unless nebulous_on?
      raise ConnectionError, "Client not connected" unless @client

      @client.connection_frame().headers["session"] \
        << "_" \
        << Time.now.to_f.to_s

    end


  end
  ##


end

