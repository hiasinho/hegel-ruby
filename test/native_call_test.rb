# frozen_string_literal: true

require_relative "test_helper"

class NativeCallTest < Minitest::Test
  class Utf8Adapter
    def initialize
      @value = FFI::MemoryPointer.from_string("café")
    end

    def read_value(_context, output)
      output.write_pointer(@value)
      Hegel::Native::HEGEL_OK
    end
  end

  def test_distinguishes_stop_test_control_flow_from_native_errors
    context = Hegel::Native.hegel_context_new
    call = Hegel::Native::Call.new(Hegel::Native, context)

    assert_raises(Hegel::Native::StopTest) do
      call.check!(:injected_call, Hegel::Native::HEGEL_E_STOP_TEST)
    end
    assert_raises(Hegel::Native::Error) do
      call.check!(:injected_call, -2)
    end
  ensure
    Hegel::Native.hegel_context_free(context) if context && !context.null?
  end

  def test_stop_test_is_not_caught_by_an_ordinary_rescue
    assert_raises(Hegel::Native::StopTest) do
      begin
        raise Hegel::Native::StopTest
      rescue StandardError
        flunk "ordinary property rescue caught internal stop-test control flow"
      end
    end
  end

  def test_decodes_borrowed_native_strings_as_utf8
    value = Hegel::Native::Call.new(Utf8Adapter.new, nil).borrowed_string(:read_value)

    assert_equal "café", value
    assert_equal Encoding::UTF_8, value.encoding
  end
end
