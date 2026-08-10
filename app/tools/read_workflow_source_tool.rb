class ReadWorkflowSourceTool < RubyLLM::Tool
  description "Read the complete source content assigned to the current workflow step."

  def initialize(content:, label:)
    @content = content
    @label = label
    super()
  end

  def execute
    "#{@label}\n\n#{@content}"
  end
end
