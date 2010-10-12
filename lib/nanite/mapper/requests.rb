module Nanite
  class Mapper
    class Requests
      include AMQPHelper
      include State

      def initialize(options = {})
        @options = options
      end

      def run
        setup_request_queue
      end

      def setup_request_queue
        handler = lambda do |msg|
          begin
            handle_request(serializer.load(msg))
          rescue Exception => e
            Nanite::Log.error("RECV [request] #{e.message}")
          end
        end
        req_fanout = amq.fanout('request', :durable => true)
        if shared_state?
          amq.queue("request").bind(req_fanout).subscribe &handler
        else
          amq.queue("request-#{identity}", :exclusive => true).bind(req_fanout).subscribe &handler
        end
      end

      # forward request coming from agent
      def handle_request(request)
        if @security.authorize_request(request)
          Nanite::Log.debug("RECV #{request.to_s}")
          case request
          when Push
            mapper.send_push(request)
          else
            intm_handler = lambda do |result, job|
              result = IntermediateMessage.new(request.token, job.request.from, mapper.identity, nil, result)
              forward_response(result, request.persistent)
            end
          
            result = Result.new(request.token, request.from, nil, mapper.identity)
            ok = mapper.send_request(request, :intermediate_handler => intm_handler) do |res|
              result.results = res
              forward_response(result, request.persistent)
            end
            
            if ok == false
              forward_response(result, request.persistent)
            end
          end
        else
          Nanite::Log.warn("RECV NOT AUTHORIZED #{request.to_s}")
        end
      end
   
    end
  end
end