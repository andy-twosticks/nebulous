require 'time'
require 'spec_helper'

require 'nebulous/stomp_handler_null'

include Nebulous


describe StompHandlerNull do

  let(:handler) do
    StompHandlerNull.new
  end

  let(:msg1) do
    stomp_message('application/text', 'verb:Foo', client.calc_reply_id)
  end

  let(:msg2) do
    stomp_message('application/text', 'verb:Bar', client.calc_reply_id)
  end


  describe 'StompHandler.body_to_hash' do

    it "returns a hash" do
      expect{ StompHandlerNull.body_to_hash({}, 'baz') }.not_to raise_exception
      expect( StompHandlerNull.body_to_hash({}, 'baz') ).to be_a_kind_of Hash
    end

  end
  ##


  describe "#initialize" do

    it "takes an initialization hash" do
      expect{ StompHandlerNull.new(foo: 'bar') }.not_to raise_exception
    end

  end
  ##


  describe "#stomp_connect" do

    it "returns self" do
      expect(handler.stomp_connect).to eq handler
    end

  end
  ##


  describe "#calc_reply_id" do

    it "returns a unique string" do
      handler.stomp_connect
      expect( handler.calc_reply_id ).to respond_to :upcase
      expect( handler.calc_reply_id.size ).to be > 12
    end
  end
  ##


  describe "send_message" do
    let(:mess) { Nebulous::Message.from_parts(nil, nil, 'foo', nil, nil) }

    it "accepts a queue name and a Message" do
      expect{ handler.send_message('foo', mess) }.not_to raise_exception
    end

    it "returns the message" do
      expect( handler.send_message('foo', mess) ).to eq mess
    end

  end
  ##


  describe "#listen" do

    def run_listen(secs)
      got = nil

      handler.listen('/queue/foo') do |m|
        got = m
      end
      sleep secs

      got
    end


    it "yields a Message" do
      gotMessage = run_listen(1)

      expect(gotMessage).not_to be_nil
      expect(gotMessage).to be_a_kind_of Nebulous::Message
    end

  end
  ##


  describe "listen_with_timeout" do

    def run_listen_with_timeout(secs)
      got = nil
      handler.listen_with_timeout('/queue/foo', secs) do |m|
        got = m
      end

      got
    end


    it "yields a Message" do
      gotMessage = run_listen_with_timeout(1)

      expect( gotMessage ).not_to be_nil
      expect( gotMessage ).to be_a_kind_of Nebulous::Message
    end


  end
  ##


end 

