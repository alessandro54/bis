# app/lib/service_result.rb
class ServiceResult
  attr_reader :error, :message, :payload, :context

  def initialize(error: nil, message: nil, payload: nil, context: {})
    @error   = error
    @message = message
    @payload = payload
    @context = context || {}
  end

  def self.success(payload = nil, message: nil, context: {})
    new(
      error:   nil,
      message: message,
      payload: payload,
      context: context
    )
  end

  def self.failure(error, message: nil, payload: nil, context: {})
    raise ArgumentError, "error can't be nil" if error.nil?

    new(
      error:   error,
      message: message,
      payload: payload,
      context: context
    )
  end

  def ok?
    error.nil?
  end

  def success?
    ok?
  end

  def failure?
    !ok?
  end
end
