# frozen_string_literal: true

require "ffi"
require_relative "version"

module Hegel
  module Native
    RELEASE = "0.44.0"
    DEFAULT_LIBRARY_PATH = File.expand_path("../../vendor/libhegel-v0.44.0/libhegel-linux-amd64.so", __dir__)
    LIBRARY_PATH = File.expand_path(ENV.fetch("HEGEL_LIBRARY_PATH", DEFAULT_LIBRARY_PATH), Dir.pwd)

    HEGEL_OK = 0
    HEGEL_E_STOP_TEST = -1

    HEGEL_RUN_STATUS_PASSED = 0
    HEGEL_RUN_STATUS_FAILED = 1
    HEGEL_RUN_STATUS_ERROR = 2

    HEGEL_STATUS_VALID = 0
    HEGEL_STATUS_OVERRUN = 2
    HEGEL_STATUS_INTERESTING = 3

    class Error < StandardError; end
    class StopTest < StandardError; end

    extend FFI::Library

    unless File.file?(LIBRARY_PATH)
      raise LoadError, <<~MESSAGE.chomp
        libhegel #{RELEASE} was not found at #{LIBRARY_PATH}.
        Install the pinned library under vendor/libhegel-v#{RELEASE}/ or set HEGEL_LIBRARY_PATH.
      MESSAGE
    end

    ffi_lib LIBRARY_PATH

    attach_function :hegel_context_new, [], :pointer
    attach_function :hegel_context_free, [:pointer], :int
    attach_function :hegel_context_last_error, [:pointer], :string

    attach_function :hegel_settings_new, [:pointer, :pointer], :int
    attach_function :hegel_settings_free, [:pointer, :pointer], :int
    attach_function :hegel_settings_set_test_cases, [:pointer, :pointer, :uint64], :int
    attach_function :hegel_settings_set_database, [:pointer, :pointer, :string], :int
    attach_function :hegel_settings_set_report_multiple_failures, [:pointer, :pointer, :bool], :int
    attach_function :hegel_settings_set_seed, [:pointer, :pointer, :uint64, :bool], :int

    attach_function :hegel_run_start, [:pointer, :pointer, :pointer, :pointer, :pointer], :int
    attach_function :hegel_next_test_case, [:pointer, :pointer, :pointer], :int
    attach_function :hegel_run_result, [:pointer, :pointer, :pointer], :int
    attach_function :hegel_run_free, [:pointer, :pointer], :int

    attach_function :hegel_test_case_from_blob, [:pointer, :pointer, :string, :pointer, :pointer, :pointer], :int
    attach_function :hegel_test_case_free, [:pointer, :pointer], :int
    attach_function :hegel_generate_integer, [:pointer, :pointer, :int64, :int64, :pointer], :int
    attach_function :hegel_mark_complete, [:pointer, :pointer, :uint32, :string], :int

    attach_function :hegel_start_span, [:pointer, :pointer, :uint64], :int
    attach_function :hegel_stop_span, [:pointer, :pointer, :bool], :int
    attach_function :hegel_label_from_name, [:pointer, :string, :pointer], :int
    attach_function :hegel_label_combine, [:pointer, :pointer, :size_t, :pointer], :int
    attach_function :hegel_new_collection, [:pointer, :pointer, :uint64, :uint64, :pointer], :int
    attach_function :hegel_collection_more, [:pointer, :pointer, :pointer, :pointer], :int
    attach_function :hegel_collection_free, [:pointer, :pointer], :int

    attach_function :hegel_run_result_free, [:pointer, :pointer], :int
    attach_function :hegel_run_result_status, [:pointer, :pointer, :pointer], :int
    attach_function :hegel_run_result_error, [:pointer, :pointer, :pointer], :int
    attach_function :hegel_run_result_failure_count, [:pointer, :pointer, :pointer], :int
    attach_function :hegel_run_result_failure, [:pointer, :pointer, :size_t, :pointer], :int

    attach_function :hegel_failure_free, [:pointer, :pointer], :int
    attach_function :hegel_failure_origin, [:pointer, :pointer, :pointer], :int
    attach_function :hegel_failure_reproduction_blob, [:pointer, :pointer, :pointer], :int
    attach_function :hegel_version, [:pointer, :pointer], :int
  end
end
