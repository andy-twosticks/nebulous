require 'spec_helper'

include Nebulous


describe NebRequest do

  before do
    stomph = { hosts: [{ login:    'guest',
                         passcode: 'guest',
                         host:     '10.0.0.150',
                         port:     61613,
                         ssl:      false }],
               reliable: false }

    redish = { host: '127.0.0.1',
               port: 6379,
               db:   0 }

    Nebulous.init( :stompConnectHash => stomph, 
                   :redisConnectHash => redish,
                   :messageTimeout   => 1 )

    Nebulous.add_target( :accord, 
                         :sendQueue => "/queue/laplace.in",
                         :receiveQueue => "/queue/laplace.out" )

  end


  describe "#initialize" do

    it "raises an exception for a bad target" do
      expect{ NebRequest.new('badtarget', 'foo') }.to \
          raise_exception(NebulousError)

    end

  end


  describe "#send_no_cache" do

    context "if Nebulous gets no response" do

      before do
        # here we send an actual STOMP request to a non-existant target
        Param.add_target(:dummy, :sendQueue => "foo", :receiveQueue => "foo")
      end

      it "returns a NebulousTimeout" do
        expect{ NebRequest.new('dummy', 'foo').send_no_cache }.to \
            raise_exception(NebulousTimeout)

      end
    end

    context "if Nebulous gets a response" do

      before do
        # mock the whole STOMP process ... eek...
        @client = instance_double( Stomp::Client, 
                                   :close   => nil,
                                   :publish => nil,
                                   :'open?' => true )

        # We assume Nebulous wants session ID to make the replyID somehow
        # ...it doesn't have to; we don't enforce that.
        allow(@client).to receive_message_chain("connection_frame.headers").
            and_return({"session" => "123"})

      end

      it "returns a NebResponse object" do
        request = NebRequest.new('accord', 'foo', nil, nil, @client)

        # The message that "stomp" returns to Nebulous. This has to be a real
        # Stomp::Message because (we assume) NebResponse uses class to tell
        # what is has been passed. Luckily it takes an actual frame; that seems
        # unlikely to change soon and is fairly stable for testing.
        @msg = Stomp::Message.new( [ 'MESSAGE',
                                     'destination:/queue/foo',
                                     'message-id:999',
                                     'neb-in-reply-to:' + request.replyID,
                                     '',
                                     'Foo' ].join("\n") + "\0" )
                                    
        expect(@client).to receive(:subscribe).and_yield(@msg)

        response = request.send_no_cache
        expect( response ).to be_a NebResponse
      end

    end
        

  end # of #send_no_cache


  describe "#send" do

    context "if Nebulous gets no response" do
      before do
        # here we send an actual STOMP request to a non-existant target
        Param.add_target(:dummy, :sendQueue => "foo", :receiveQueue => "foo")
      end

      it "returns a NebulousTimeout" do
        expect{ NebRequest.new('dummy', 'foo').send }.to \
            raise_exception(NebulousTimeout)

      end

    end

    context "if Nebulous gets a response" do

      before do

        # mock the whole STOMP process ... eek...
        @client = instance_double( Stomp::Client, 
                                   :close   => nil,
                                   :publish => nil,
                                   :'open?' => true )

        # We assume Nebulous wants session ID to make the replyID somehow
        # ...it doesn't have to; we don't enforce that.
        allow(@client).to receive_message_chain("connection_frame.headers").
            and_return({"session" => "123"})

      end

      it "returns a NebResponse object" do
        request = NebRequest.new('accord', 'foo', nil, nil, @client)

        # The message that "stomp" returns to Nebulous. This has to be a real
        # Stomp::Message because (we assume) NebResponse uses class to tell
        # what is has been passed. Luckily it takes an actual frame; that seems
        # unlikely to change soon and is fairly stable for testing.
        @msg = Stomp::Message.new( [ 'MESSAGE',
                                     'destination:/queue/foo',
                                     'message-id:999',
                                     'neb-in-reply-to:' + request.replyID,
                                     '',
                                     'Foo' ].join("\n") + "\0" )
                                    
        expect(@client).to receive(:subscribe).and_yield(@msg)

        response = request.send
        expect( response ).to be_a NebResponse
      end

    end

=begin
    context "when given the same request twice" do
      it "takes the second response from the cache"
    end
=end

  end
    

end


