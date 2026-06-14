# frozen_string_literal: true

module LocallyInteractable
  extend ActiveSupport::Concern

  included do
    attr_reader :provider, :data, :raw_response, :content, :llm, :prompt, :response, :connection

    def initialize(data = {})
      @data = data
      @connection = data[:connection] || RestClient

      setup_prompt
      raise Agentic::Errors::ConfigurationError, "No prompt present" if prompt.blank?
      raise Agentic::Errors::ConfigurationError, "No system_directive on prompt" if prompt.system_directive.blank?

      setup_model_connection
      raise Agentic::Errors::ConfigurationError, "No LLM present" if llm.blank?

      setup_content
      raise Agentic::Errors::ConfigurationError, "Content is required" if content.blank?
    end
  end

  def call
    @provider = @provider_klass.new(
      connection: connection,
      operation_type: operation_type,
      requirements: requirements
    )

    @raw_response = provider.call
    log_llm_event("LLM call completed", provider.llm_metadata.merge(status: "completed"))
    @raw_response
  rescue StandardError => e
    log_llm_event("LLM call failed", provider.failure_metadata(e)) if provider
    raise
  end

  def operation_type
    @provider_klass.default_operation_type
  end

  def setup_prompt
    @agent_type = AgentType.find_by!(name: agent_type_name)
    @prompt = @agent_type.prompts.active.first
  end

  def setup_model_connection
    @llm = @agent_type.llm
    @provider_klass = llm.provider_klass
  end

  def setup_content
    @content = data[:content]
  end

  def agent_type_name
    self.class.name.demodulize.underscore
  end

  def requirements
    raise NotImplementedError, "#{self.class.name} must implement #requirements"
  end

  def log_llm_event(message, payload)
    return unless respond_to?(:log_event)

    log_event(message, payload, event_type: "llm_call")
  end
end
