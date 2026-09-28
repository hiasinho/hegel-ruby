# frozen_string_literal: true

require_relative "test_helper"

class NativeCallTest < Minitest::Test
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
end
