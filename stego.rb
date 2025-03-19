require 'chunky_png'
require 'digest'
require 'io/console'


class ImageSteganography
  def initialize(image_path, password, bits_per_channel = 1)
    @image = ChunkyPNG::Image.from_file(image_path)
    @seed = string_to_seed(password)
    @bits_per_channel = bits_per_channel
    @rng = Random.new(@seed)
  end

  def encode(message, output_path)
    binary_message = message.unpack("B*")[0]
    binary_length = [binary_message.length].pack("N").unpack("B*")[0]
    full_message = binary_length + binary_message

    pixels = @image.pixels
    shuffled_indices = (0...pixels.length).to_a.shuffle(random: @rng)

    #Encode bits_per_channel into the red channel of the first pixel
    first_pixel_index = shuffled_indices[0]
    x, y = first_pixel_index % @image.width, first_pixel_index / @image.width
    first_pixel = @image[x, y]
    r, g, b, a = ChunkyPNG::Color.to_truecolor_alpha_bytes(first_pixel)
    r = @bits_per_channel
    @image[x, y] = ChunkyPNG::Color.rgba(r, g, b, a)

    message_index = 0
    shuffled_indices[1..-1].each do |i|
      break if message_index >= full_message.length
      x, y = i % @image.width, i / @image.width
      pixel = @image[x, y]
      new_pixel = encode_pixel(pixel, full_message, message_index)
      @image[x, y] = new_pixel
      message_index += @bits_per_channel * 3
    end

    @image.save(output_path)
  end

  def decode
    pixels = @image.pixels
    shuffled_indices = (0...pixels.length).to_a.shuffle(random: @rng)

    #Decode bits_per_channel from the red channel of the first pixel
    first_pixel_index = shuffled_indices[0]
    x, y = first_pixel_index % @image.width, first_pixel_index / @image.width
    first_pixel = @image[x, y]
    r, g, b, a = ChunkyPNG::Color.to_truecolor_alpha_bytes(first_pixel)
    bits_per_channel = r

    binary_length = ''
    message_index = 0
    shuffled_indices[1..-1].each do |i|
      x, y = i % @image.width, i / @image.width
      pixel = @image[x, y]
      binary_length += decode_pixel(pixel, 32 - binary_length.length, bits_per_channel)
      break if binary_length.length >= 32
    end
    message_length = binary_length.to_i(2) + 32

    binary_message = ''
    shuffled_indices[1..-1].each do |i|
      break if binary_message.length >= message_length
      x, y = i % @image.width, i / @image.width
      pixel = @image[x, y]
      binary_message += decode_pixel(pixel, [bits_per_channel * 3, message_length - binary_message.length].min, bits_per_channel)
    end

    [binary_message].pack("B*")
  end

  private

  def encode_pixel(pixel, message, index)
    r, g, b, a = ChunkyPNG::Color.to_truecolor_alpha_bytes(pixel)
    [r, g, b].each_with_index do |color, i|
      bits = message[index, @bits_per_channel] || '0' * @bits_per_channel
      color = (color & ~((1 << @bits_per_channel) - 1)) | bits.to_i(2)
      index += @bits_per_channel
      case i
      when 0 then r = color
      when 1 then g = color
      when 2 then b = color
      end
    end
    ChunkyPNG::Color.rgba(r, g, b, a)
  end

  def decode_pixel(pixel, bits_to_extract, bits_per_channel)
    r, g, b, a = ChunkyPNG::Color.to_truecolor_alpha_bytes(pixel)
    binary = ''
    [r, g, b].each do |color|
      binary += (color & ((1 << bits_per_channel) - 1)).to_s(2).rjust(bits_per_channel, '0')
      break if binary.length >= bits_to_extract
    end
    binary[0...bits_to_extract]
  end

  #Convert a string password to a seed using a hash function
  def string_to_seed(password)
    Digest::MD5.hexdigest(password).to_i(16)
  end
end

def can_message_fit?(image_path, message)
  num_planes_needed = calculate_bits_per_channel(image_path, message)
  available_planes = 8 #Assuming the picture has a bit depth of 24 or 32, which is the intended bit depth for the encoding algorithm
  num_planes_needed <= available_planes
end

def calculate_bits_per_channel(image_path, message)
  image = ChunkyPNG::Image.from_file(image_path)
  width = image.width
  height = image.height
  total_pixels = width * height

  max_bits_per_plane = total_pixels * 3
  binary_message = message.unpack1('B*')
  message_length_bits = binary_message.length

  required_bits = 32 + message_length_bits

  num_planes_needed = (required_bits / max_bits_per_plane.to_f).ceil
  num_planes_needed
end


#Program loop starts here
loop do
  puts "Press E to encode or D to decode.\nPress Q to exit."

  input = IO.console.getch
  case input
  when 'e', 'E'
    puts 'Enter path for the input image:'
    input_path = gets.chomp
    puts 'Enter the desired path for output:'
    output_path = gets.chomp
    puts 'Enter your message:'
    message = gets.chomp

    if !can_message_fit?(input_path, message)
      puts 'Message is too large. Please enter a smaller message or use a larger image'
      break
    end
    bits_per_channel = calculate_bits_per_channel(input_path, message)

    puts "Enter password"
    password = gets.chomp
    puts "Encoding message using the password: #{password} . . ."
    encoder = ImageSteganography.new(input_path, password, bits_per_channel)
    encoder.encode(message, output_path)
    puts "Message encoded and saved to #{output_path}"


  when 'd', 'D'
    puts 'Enter encoded image path:'
    encoded_image_path = gets.chomp
    puts 'Enter password:'
    password = gets.chomp
    puts "Decoding message from #{encoded_image_path} using the password: #{password} . . ."

    decoder = ImageSteganography.new(encoded_image_path, password, 1)
    message = decoder.decode
    puts "Decoded message: #{message}"
  

  when 'q', 'Q'
    puts 'Exiting . . .'
    break
  end
end
