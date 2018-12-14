# frozen_string_literal: true

module Esi
  # An abstraction of Esi::Client context methods
  module ClientContext
    def self.included(base)
      base.include InstanceMethods
      base.extend ClassMethods
    end

    module ClassMethods
      # Set the current thread's `Esi::Client`
      #
      # @param client [Esi::Client] the client to set
      #
      # @return [Esi::Client] the current thread's `Esi::Client`
      def current=(client)
        Thread.current[:esi_client] = client
      end

      # Get the current thread's `Esi::Client`
      # @return [Esi::Client] the current thread's `Esi::Client`
      def current
        Thread.current[:esi_client] ||= new
      end

      # Switch to default Esi::Client (Esi::Client.new)
      # @return [Esi::Client] the current thread's `Esi::Client`
      def switch_to_default
        self.current = new
      end
    end

    module InstanceMethods
      # Switch current thread's client to instance of Esi::Client
      # @return [self] the instance calling switch to
      def switch_to
        Esi::Client.current = self
      end

      # Yield block with instance of Esi::Client and revert to
      #  previous client or default client
      #
      # @example Call an Esi::Client method using an instance of client
      #  new_client = Esi::Client.new(token: 'foo', refresh_token: 'foo', exceptionxpires_at: 30.minutes.from_now)
      #  new_client.with_client do |client|
      #    client.character(1234)
      #  end
      #  #=> Esi::Response<#>
      #
      # @yieldreturn [#block] the passed block.
      def with_client
        initial_client = Esi::Client.current
        switch_to
        yield(self) if block_given?
      ensure
        initial_client.switch_to if initial_client
        Esi::Client.switch_to_default unless initial_client
      end
    end
  end
end
