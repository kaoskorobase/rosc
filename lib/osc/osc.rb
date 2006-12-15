=begin rdoc

= Overview
OpenSoundControl implementation in Ruby.

= Author
Stefan Kersten <mailto:steve@k-hornz.de>

= License
Copyright (c) 2004 Stefan Kersten. All rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
USA
=end

class Object # :nodoc:
  def osc_encode_on(types, buf)
    self.to_s.osc_encode_on(types, buf)
  end
end

class Integer
  def osc_alignment
    4 - (self & 3)
  end
  def osc_aligned
    self + 4 - (self & 3)
  end
  def osc_aligned?
    (self > 3) and (self & 3).zero?
  end
  def osc_encode_on(types, buf) # :nodoc:
    types << OSC::TYPE_INT32
    buf.put_i32(self)
  end
end

class FalseClass # :nodoc:
  def osc_encode_on(types, buf)
    0.osc_encode_on(types, buf)
  end
end

class Float # :nodoc:
  def osc_encode_on(types, buf)
    types << OSC::TYPE_FLOAT32
    buf.put_f32(self)
  end
end

class NilClass # :nodoc:
  def osc_encode_on(types, buf)
  end
end

class String # :nodoc:
  def osc_encode_on(types, buf)
    types << OSC::TYPE_STRING
    buf.put_data(self)
  end
end

class TrueClass # :nodoc:
  def osc_encode_on(types, buf)
    1.osc_encode_on(types, buf)
  end
end

module OSC
  BUNDLE_STRING = "#bundle\0" # :nodoc:
  BUNDLE_REGEXP = Regexp.compile("^" + Regexp.quote(BUNDLE_STRING)) # :nodoc:

  TYPE_TAG_START = 44 # ','
  TYPE_INT32 = 105    # 'i'
  TYPE_FLOAT32 = 102  # 'f'
  TYPE_STRING = 115   # 's'
  TYPE_BLOB = 98      # 'b'

  SECONDS_FROM_UTC_TO_UNIX_EPOCH = 2208988800.0 # :nodoc:
  SECONDS_TO_TIME = 2.0 ** 32.0 # :nodoc:
  TIME_TO_SECONDS = 1.0 / SECONDS_TO_TIME # :nodoc:

  INT_MASK = 0x80000000 # :nodoc:
  UINT_MASK = 0xFFFFFFFF # :nodoc:

  # exceptions
  class Error < RuntimeError; end
  class UnderrunError < Error; end
  class ParseError < Error; end

  # Untyped binary data wrapper.
  class Blob
    attr_reader :data

    # initialization
    def initialize(data="")
      self.data = data
    end

    # :section:Accessing
    # Return current size in bytes.
    def size
      @data.size
    end
    # Return data as String.
    def data=(data)
      @data = data.to_s
    end

    # :section:OSC support
    def osc_encode_on(types, buf)
      types << OSC::TYPE_BLOB
      buf.put_i32(@data.size)
      buf.put_data(@data)
    end
  end # class Blob

  # OSC time representation.
  class Time
    # Return current OSC time.
    def self.now
      Object::Time.now.to_f + SECONDS_FROM_UTC_TO_UNIX_EPOCH
    end
    # Convert network time (unsigned long long) to OSC time.
    def self.from_i(t)
      t * TIME_TO_SECONDS
    end
    # Convert to network time (unsigned long long).
    def self.to_i(t)
      t = (t.to_i << 32) + ((t * SECONDS_TO_TIME).to_i & UINT_MASK)
      t.zero? ? 1 : t
    end
    MIN_I = self.to_i(0)
    MIN_F = self.from_i(MIN_I)
  end

  class Packet
    include Enumerable

    attr_accessor :time
    attr_reader :args

    # instance creation
    def initialize(args=[])
      @args = args
    end

    def Packet.decode(data)
      unless data.size.osc_aligned?
        raise ParseError, "invalid packet size"
      end
      buf = Buffer.new(data)
      if (data.size > 15) and BUNDLE_REGEXP =~ data
        Bundle.decode_from(buf)
      else
        Msg.decode_from(buf)
      end
    end

    # testing
    def bundle?
      false
    end
    def msg?
      false
    end
    def empty?
      @args.empty?
    end

    # accessing
    def size
      @args.size
    end
    def [](index)
      @args[index]
    end
    def <<(obj)
      @args << obj
      self
    end

    # iterating
    def each_msg
    end

    # converting
    def to_a
      @args.clone
    end

    # inspecting
    def inspect
      self.to_a.inspect
    end

    # encoding
    def encode
      buf = Buffer.new
      self.encode_on(buf)
      buf.data
    end
    def encode_on(buf)
    end
  end # class Packet

  # convenience
  def OSC.decode(data)
    Packet.decode(data)
  end

  class Bundle < Packet
    attr_reader :time

    # instance creation
    def Bundle.[] (time, *args)
      self.new(time, args)
    end

    def Bundle.decode_from(buf)
      buf.skip(BUNDLE_STRING.size)
      time = Time.from_i(buf.get_i64)
      args = []
      until buf.empty?
        pkt = Packet.decode(buf.get_aligned_data(buf.get_i32))
	# if pkt is a message set time to this bundle's time
        pkt.time = time if pkt.msg?
        args.push(pkt)
      end
      self.new(time, args)
    end
    
    # initialization
    def initialize(time, args=[])
      self.time = time
      super(args)
    end

    # testing
    def bundle?
      true
    end

    # accessing
    def flatten
      res = []
      self.each_msg { | msg |
        res.push(msg)
      }
      res
    end

    # iterating
    def each_msg
      @args.each { | pkt |
	pkt.each_msg { | msg |
	  yield msg
	}
      }
    end

    # converting
    def to_a
      [@time] + super
    end

    # decoding
    def encode_on(buf)
      buf.put_aligned_data(BUNDLE_STRING)
      buf.put_i64(OSC::Time.to_i(self.time))
      @args.each { | pkt |
        pkt = pkt.encode
        buf.put_i32(pkt.size)
        buf.put_aligned_data(pkt)
      }
    end

    protected

    def flatten_on(a)
    end
  end

  class Msg < Packet
    attr_reader :addr

    # instance creation
    def Msg.[] (addr, *args)
      self.new(addr, args)
    end

    def Msg.decode_from(buf)
      addr = buf.get_s
      types = buf.get_s
      unless types[0] == TYPE_TAG_START
        raise OSC::ParseError, "invalid type tag string"
      end
      args = Array.new(types.size-1)
      args.size.times { |i| args[i] = buf.get_obj(types[i+1]) }
      self.new(addr, args)
    end

    # initialization
    def initialize(addr, args=[])
      self.addr = addr
      super(args)
    end

    # testing
    def msg?
      true
    end

    # accessing
    def addr=(addr)
      @addr = addr.to_s
    end
    def time
      @time or (@time = Time::MIN_F)
    end
    def time=(time)
      @time = time
    end

    # iterating
    def each_msg
      yield self
    end

    # converting
    def to_a
      [@addr] + super
    end

    # encoding
    def encode_on(buf)
      buf.put_data(self.addr.to_s)
      types = ","
      arg_buf = Buffer.new
      @args.each { | arg | arg.osc_encode_on(types, arg_buf) }
      buf.put_data(types)
      buf.put_aligned_data(arg_buf.data)
    end
  end

  class Buffer
    OBJECT_READER_MAP = {
      TYPE_INT32 => :get_i32,
      TYPE_FLOAT32 => :get_f32,
      TYPE_STRING => :get_s,
      TYPE_BLOB => :get_b
    }

    # buffer for reading/writing OSC
    attr_reader :data

    # initialization
    def initialize(data="")
      @data = @data0 = data
    end

    # testing
    def empty?
      @data.empty?
    end

    # accessing
    def size
      @data.size
    end
    def reset
      @data = @data0
      self
    end
    def skip(n)
      @data = @data[n..-1]
      @data = "" unless @data
      self
    end

    # errors
    def underrun!
      raise UnderrunError, "buffer underrun", caller
    end

    # :section:Reading

    # Read 32 bit integer.
    def get_i32
      res, @data = @data.unpack("Na*")
      self.underrun! unless res
      res - ((res & INT_MASK) << 1)
    end
    # Read 64 bit integer.
    def get_i64
      hi, lo, @data = @data.unpack("NNa*")
      self.underrun! unless hi and lo
      (hi << 32) | lo
    end
    # Read 32 bit float.
    def get_f32
      res, @data = @data.unpack("ga*")
      self.underrun! unless res
      res
    end
    # Read 64 bit float.
    def get_f64
      res, @data = @data.unpack("Ga*")
      self.underrun! unless res
      res
    end
    # Read aligned data.
    # _n_ must already be OSC aligned.
    def get_aligned_data(n)
      # n must be aligned
      res, @data = @data.unpack("a#{n}a*")
      self.underrun! unless res
      res
    end
    # Read aligned data.
    # _n_ does not have to be OSC aligned.
    def get_data(n)
      res, @data = @data.unpack("a#{n}x#{n.osc_alignment}a*")
      self.underrun! unless res
      res
    end
    # Read zero padded string.
    def get_s
      n = @data.index(0)
      self.underrun! unless n
      self.get_data(n)
    end
    # Read binary data.
    # A 32 bit byte count is followed by that amount of data, padded to a multiple of 4 bytes.
    def get_b
      n = self.get_i32
      OSC::Blob.new(self.get_data(n))
    end
    # Read object according to type tag.
    def get_obj(type_tag)
      if id = OBJECT_READER_MAP[type_tag]
        return self.send(id)
      end
      raise OSC::ParseError, "invalid type tag"
    end

    # :section:Writing

    # Write 32 bit integer.
    def put_i32(arg)
      @data += [arg].pack("N")
      self
    end
    # Write 64 bit integer.
    def put_i64(arg)
      @data += [(arg >> 32) & UINT_MASK, arg & UINT_MASK].pack("NN")
      self
    end
    # Write 32 bit float.
    def put_f32(arg)
      @data += [arg].pack("g")
      self
    end
    # Write 64 bit float.
    def put_f64(arg)
      @data += [arg].pack("G")
      self
    end
    # Write aligned data.
    # +arg.size+ must be OSC aligned.
    def put_aligned_data(arg)
      # arg.size must be aligned
      @data += [arg].pack("a#{arg.size}")
      self
    end
    # Write aligned data.
    def put_data(arg)
      n = arg.size
      @data += [arg].pack("a#{n}@#{n.osc_aligned}")
      self
    end
  end # class Buffer

  class Map < Hash
    # Install command handler.
    def on(cmd, &proc)
      self[cmd] = proc
    end
    # Dispatch OSC packet.
    def dispatch(pkt)
      pkt.each_msg { |msg| queue_msg(msg) }
    end
    # Dispatch OSC message.
    def dispatch_msg(msg)
      proc = self[msg.addr]
      if proc
        begin
          proc.call(msg)
        rescue
          $!
        end
      end
    end
    protected
    # Subclasses may override to queue bundles according to their
    # timestamp.
    def queue_msg(msg)
      dispatch_msg(msg)
    end
  end
end # module OSC

def OSC.test # :nodoc:
  require "socket"

  t = OSC::Time.now
  m0 = OSC::Msg["/fooBar", -12, 3.4, "sexihexi"]
  m1 = OSC::Msg["/hell/yeah", "what tha? time slice exceeded.", 42]
  m2 = OSC::Msg["/Whooha", 7, "in", "full", "f", "x"]
  b0 = OSC::Bundle[t, m1, m2]
  b1 = OSC::Bundle[t, m1, m2, OSC::Bundle[t + 12, m0]]

  p m0.encode
  p b0.encode
  p b1.encode

  p OSC::Packet.decode(m0.encode)
  p OSC::Packet.decode(b0.encode)
  p OSC::Packet.decode(b1.encode)
 
  OSC::Packet.decode(b1.encode).each_msg { | msg |
    $stdout.printf("msg @ %f: %s\n", msg.time, msg.inspect)
  }

  addr = ["localhost", 22000]
  sock = UDPSocket.open
  sock.send(m0.encode, 0, *addr)
  sock.send(b0.encode, 0, *addr)
  sock.send(b1.encode, 0, *addr)
  sock.close

  map = OSC::Map.new
  map.on("/fooBar") do |msg| puts msg.inspect end
  map.on("/hell/yeah") do |msg| puts msg.inspect end
  map.on("/Whooha") do |msg| puts msg.inspect end

  map.dispatch(m0)
  map.dispatch(m1)
  map.dispatch(b1)
end

OSC.test if __FILE__ == $0

# EOF
