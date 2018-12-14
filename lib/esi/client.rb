# frozen_string_literal: true

require 'esi/client/client_context'

module Esi
  # The Esi Client class
  # @!attribute [rw] refresh_callback
  #  @return [#callback] the refresh_token callback method
  # @!attribute [rw] access_token
  #  @return [String] the esi access_token
  # @!attribute [rw] refresh_token
  #  @return [String] the esi refresh_token string
  # @!attribute [rw] expires_at
  #  @return [Time] the timestamp of the esi token expire
  # @!attribute [r] logger
  #  @return [Logger] the logger class for the gem
  # @!attribute [r] oauth
  #  @return [Esi::Oauth] the oauth instance for the client
  class Client
    include Esi::ClientContext
    # @return [Fixnum] The max amount of request attempst Client will make
    MAX_ATTEMPTS = 2

    attr_accessor :refresh_callback, :access_token, :refresh_token, :expires_at
    attr_reader :logger, :oauth

    # Create a new instance of Client
    # @param token [String] token the esi access_token
    # @param refresh_token [String] refresh_token the esi refresh_token
    # @param expires_at [Time] expires_at the time stamp the esi token expires_at
    def initialize(token: nil, refresh_token: nil, expires_at: nil)
      @logger = Esi.logger
      @access_token = token
      @refresh_token = refresh_token
      @expires_at = expires_at
      @oauth = init_oauth
    end

    # Intercept Esi::Client respond_to? and return true if
    #   an Esi::Call exists with the approriate method_name
    #
    # @param method_name [Symbol|String] method_name the name of the method called
    # @param include_private [Boolean|nil] includes private methods if true
    # @return [Boolean] whether the method exists
    def respond_to_missing?(method_name, include_private = false)
      call_class(method_name) || super
    end

    # Intercept Esi::Client method_missing and attempt to call an Esi::Request
    #  with an Esi::Calls
    #
    # @param metho_name [Symbol|String] the name of the method called
    # @param args [Array] the arguments to call the method with
    # @param block [#block] the block to pass to the underlying method
    # @raise [NameError] If the Esi::Calls does not exist
    # @return [Esi::Response] the response given for the call
    def method_missing(method_name, *args, &block)
      detect_call(method_name, *args, &block) || super
    end

    # Test if the Esi::Client has a method
    # @deprecated Use #respond_to? instead.
    # @param [Symbol] method_name the name of the method to test
    # @return [Boolean] wether or not the method exists
    def method?(name)
      warn '[DEPRECATION `method?` is deprecated. Please use `respond_to?` instead.'
      call_exists?(method_name)
    end

    # Test if the Esi::Client has a pluralized version of a method
    # @param [Symbol] name the name of the method to test
    # @return [Boolean] wether or not the pluralized method exists
    def plural_method?(method_name)
      warn '[DEPRECATION `plural_method?` is deprecated. Please use `respond_to?` instead.'
      plural = method_name.to_s.pluralize.to_sym
      call_exists?(plural)
    end

    # Log a message
    # @param [String] message the message to log
    # @return [void] the Logger.info method with message
    def log(message)
      logger.info message
    end

    # Log a message with debug
    # @param [String] message the message to log
    # @return [void] the Logger.debug method with message
    def debug(message)
      logger.debug message
    end

    private

    def call_class(method_name)
      Esi::Calls.const_get(method_to_class_name(method_name))
    rescue NameError
      nil
    end

    def detect_call(method_name, *args, &block)
      klass = nil
      ActiveSupport::Notifications.instrument('esi.client.detect_call') { klass = call_class(method_name) }
      cached_response(klass, *args, &block) if klass
    end

    def make_call(call, &block)
      call.paginated? ? request_paginated(call, &block) : request(call, &block)
    end

    def cached_response(klass, *args, &block)
      call = klass.new(*args)
      Esi.cache.fetch(call.cache_key, expires_in: klass.cache_duration) do
        make_call(call, &block)
      end
    end

    def method_to_class_name(method_name)
      method_name.to_s.split('_').map(&:capitalize).join
    end

    def init_oauth
      OAuth.new(
        access_token: @access_token,
        refresh_token: @refresh_token,
        expires_at: @expires_at,
        callback: lambda { |token, exceptionxpires_at|
          @access_token = token
          @expires_at = expires_at
          refresh_callback.call(token, exceptionxpires_at) if refresh_callback.respond_to?(:call)
        }
      )
    end

    def request_paginated(call, &block)
      call.page = 1
      paginated_response(response, call, &block)
    end

    def paginated_response(response, call, &block)
      loop do
        page_response = request(call, &block)
        break response if page_response.data.blank?
        response = response ? response.merge(page_response) : page_response
        call.page += 1
      end
    end

    # @todo make rubocop compliant
    # rubocop:disable Metrics/AbcSize
    def request(call, &block)
      response = Timeout.timeout(Esi.config.timeout) do
        oauth.request(call.method, call.url, timeout: Esi.config.timeout)
      end
      response = Response.new(response, call)
      response.data.each { |item| yield(item) } if block
      response.save
    rescue OAuth2::Error => e
      exception = error_class_for(e.response.status).new(Response.new(e.response, call), e)
      raise exception.is_a?(Esi::ApiBadRequestError) ? process_bad_request_error(exception) : exception
    rescue Faraday::SSLError, Faraday::ConnectionFailed, Timeout::Error => e
      raise Esi::TimeoutError.new(Response.new(e.response, call), exception)
    end
    # rubocop:enable Metrics/AbcSize

    def error_class_for(status)
      case status
      when 400 then Esi::ApiBadRequestError
      when 401 then Esi::UnauthorizedError
      when 403 then Esi::ApiForbiddenError
      when 404 then Esi::ApiNotFoundError
      when 502 then Esi::TemporaryServerError
      when 503 then Esi::RateLimitError
      else Esi::ApiUnknownError
      end
    end

    def process_bad_request_error(exception)
      case exception.message
      when 'invalid_token'  then Esi::ApiRefreshTokenExpiredError.new(response, exception)
      when 'invalid_client' then Esi::ApiInvalidAppClientKeysError.new(response, exception)
      else exception
      end
    end
  end
end
