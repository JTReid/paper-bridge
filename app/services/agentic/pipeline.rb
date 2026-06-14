# frozen_string_literal: true

module Agentic
  class Pipeline
    include Errors

    ResultEntry = Struct.new(:index, :klass, :tag, :result, keyword_init: true)

    attr_reader :results

    def initialize(agents, progress_tracker: nil, context: {})
      @agents = agents
      @results = []
      @progress_tracker = progress_tracker || Agentic::NullProgressTracker.new
      @is_valid = true

      pipeline_run = locate_pipeline_run!(context)
      @instrumentation = build_instrumentation(pipeline_run)
      @context = build_context(context)
    end

    def execute(initial_content = nil)
      @instrumentation.run_started(total_steps: @agents.count)
      @progress_tracker.start_with(steps: @agents.count)

      current_content = initial_content

      begin
        @agents.each_with_index do |agent_config, index|
          agent_class, agent_params, agent_tags = parse_agent_config(agent_config)

          agent_params = agent_params.dup
          after_callback = agent_params.delete(:after_execute)

          @context.prepare_for_agent(agent_params, agent_class)
          params = @context.to_params(current_content, agent_params)
          agent = agent_class.new(params)

          @progress_tracker.step_started(agent.step_started)

          result = execute_agent(agent, agent_class, index, agent_tags)

          @instrumentation.step_completed(agent_class, index: index, tag: agent_tags[:tag])
          after_callback&.call(result, @context.shared, current_content)

          results << ResultEntry.new(
            index: index,
            klass: agent_class,
            tag: agent_tags[:tag],
            result: result
          )

          @progress_tracker.step_completed(agent.step_complete)

          if agent.pass_through_pipeline_response?
            if agent_tags[:tag] == :validator
              @is_valid = result[:status] == "APPROVED"
              break unless @is_valid
            end
          else
            current_content = result
          end
        end
      rescue Error => e
        @instrumentation.run_failed(error: e)
        raise
      end

      @instrumentation.run_completed
    end

    def valid?
      @is_valid
    end

    def to_response
      raise NotImplementedError, "#{self.class.name} must implement #to_response"
    end

    private

    def execute_agent(agent, agent_class, index, agent_tags)
      agent.execute
    rescue StandardError => e
      @instrumentation.step_failed(
        agent_class,
        index: index,
        tag: agent_tags[:tag],
        error: e
      )
      raise ExecutionError, e.message
    end

    def build_instrumentation(pipeline_run)
      Agentic::PipelineInstrumentation.new(
        pipeline_run: pipeline_run,
        pipeline_name: self.class.name
      )
    end

    def build_context(context)
      Agentic::PipelineContext.new(context, instrumentation: @instrumentation)
    end

    def locate_pipeline_run!(context)
      gid = context[:pipeline_run_gid]
      raise ConfigurationError, "context[:pipeline_run_gid] is required" if gid.blank?

      GlobalID::Locator.locate(gid).tap do |pipeline_run|
        raise ConfigurationError, "context[:pipeline_run_gid] could not be resolved" if pipeline_run.blank?
      end
    rescue ActiveRecord::RecordNotFound
      raise ConfigurationError, "context[:pipeline_run_gid] could not be resolved"
    end

    def parse_agent_config(config)
      normalized = Array(config)
      normalized += [ {} ] * (3 - normalized.length)
      normalized
    end
  end
end
