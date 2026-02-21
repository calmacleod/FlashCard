class RuleAgent
  SYSTEM_PROMPT = <<~PROMPT
    You are a rules expert assistant. When answering questions about rules,
    always search the rulebook first using the available tool before responding.
    Cite the specific rule, section, and article numbers in your answers.
  PROMPT

  def self.run(source_csv:, model: "gemini-2.5-flash-lite", debug: false)
    new(source_csv:, model:, debug:).run
  end

  def initialize(source_csv:, model:, debug: false)
    @source_csv = File.expand_path(source_csv)
    @model      = model
    @debug      = debug
  end

  def run
    puts "Rule Agent ready. Searching: #{File.basename(@source_csv)}"
    puts "Model: #{@model}  (type 'exit' to quit)\n\n"

    RubyLLM.configure { |c| c.logger = Logger.new(IO::NULL) } unless @debug

    chat = RubyLLM.chat(model: @model)
                  .with_instructions(SYSTEM_PROMPT)
                  .with_tool(RuleSearchTool.new(source_csv: @source_csv))
                  .with_tool(RuleDefinitionLookupTool.new(source_csv: @source_csv))

    @input_tokens  = 0
    @output_tokens = 0

    loop do
      print "You: "
      input = $stdin.gets&.strip
      break if input.nil? || input.downcase == "exit"
      next if input.empty?

      response = chat.ask(input)
      @input_tokens  += response.input_tokens.to_i
      @output_tokens += response.output_tokens.to_i
      puts "\nAgent: #{response.content}\n\n"
    end

    print_token_summary
  end

  private

  def print_token_summary
    total = @input_tokens + @output_tokens
    puts "─" * 40
    puts "Token usage:"
    puts "  Input:  #{@input_tokens.to_s.rjust(10)}"
    puts "  Output: #{@output_tokens.to_s.rjust(10)}"
    puts "  Total:  #{total.to_s.rjust(10)}"
  end
end
