# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :typhoeus

  depends_on do
    defined?(Typhoeus) && defined?(Typhoeus::VERSION)
  end

  depends_on do
    Typhoeus::VERSION >= NewRelic::Agent::Instrumentation::TyphoeusTracing::EARLIEST_VERSION
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Typhoeus instrumentation (without Hydra mode support)'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/typhoeus_wrappers'
  end

  module NewRelic::Agent::Instrumentation::TyphoeusTracing

    EARLIEST_VERSION = "0.2.0"

    def self.trace(request)
      if NewRelic::Agent.is_execution_traced? && (!request.respond_to?(:hydra) || (request.respond_to?(:hydra) && request.hydra.nil?))
        wrapped_request = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(request)
        t0, segment = ::NewRelic::Agent::CrossAppTracing.start_trace(wrapped_request)
        request.on_complete do
          wrapped_response = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(request.response)
          ::NewRelic::Agent::CrossAppTracing.finish_trace(t0, segment, wrapped_request, wrapped_response)
        end if t0
      end
    end

  end

  executes do

    if Typhoeus::VERSION <= "0.5.0"
      class Typhoeus::Request
        class << self
          def run_with_newrelic(url, params)
            params[:headers] ||= {}
            params[:headers][:newrelic_trace_request] = true
            run_without_newrelic(url, params)
          end

          alias run_without_newrelic run
          alias run run_with_newrelic
        end
      end

      class Typhoeus::Hydra
        def queue_with_newrelic(request, *args)
          trace = request.headers && request.headers.delete(:newrelic_trace_request)
          NewRelic::Agent::Instrumentation::TyphoeusTracing.trace(request) if trace
          queue_without_newrelic(request, *args)
        end

        alias queue_without_newrelic queue
        alias queue queue_with_newrelic
      end

    else
      Typhoeus.before do |request|
        NewRelic::Agent::Instrumentation::TyphoeusTracing.trace(request)

        # Ensure that we always return a truthy value from the before block,
        # otherwise Typhoeus will bail out of the instrumentation.
        true
      end
    end
  end
end
