# frozen_string_literal: true

require 'erb'
require 'json'

# Shared ERB rendering engine. Both generators render through this:
#   scripts/generate.rb  — templates/actions/**  -> actions/**/action.yml (uses render_step)
#   bin/workflow         — templates/workflows/** -> a consumer's release workflow (flat; no render_step)
module Templating
  # The rendering scope for a template. An instance's `binding` is handed to ERB,
  # so the ONLY methods a template (.yml.erb) can call are this class's PUBLIC
  # methods — render and render_step. Internal helpers stay private.
  #
  # `steps_dir` is the root for render_step partials (templates/steps for actions).
  # Templates that never call render_step (e.g. flat workflow templates) omit it.
  class Template
    def initialize(source, steps_dir: nil)
      @source = source
      @steps_dir = steps_dir
    end

    # Renders the template. Keyword args are exposed to the template as a
    # `locals` hash (read with `locals.fetch(:name) { default }`).
    def render(**locals)
      ERB.new(@source, trim_mode: '-').result(binding)
    end

    # Inlines a reusable step (<steps_dir>/<name>.yml.erb) under a `steps:`
    # key. The fragment may hold several steps and may compose other steps.
    # Keyword args reach the step as `locals` (read with locals.fetch(:x) { default }).
    #
    # `if:` is the composing action's one control-flow knob. GitHub has no way to
    # guard a group of steps in a flat composite action, so when `on-failure`
    # flattens into several sibling steps, the single `if: failure()` written at
    # the call site is stamped onto EACH of them. Everything else a step
    # decides — slack configured? dry run? — is a shell self-guard (`exit 0`),
    # never an `if:`, so there is never a condition to merge. Omit `if:` to run
    # unconditionally.
    def render_step(name, indent: 4, **locals)
      raise 'render_step called on a Template constructed without a steps_dir' unless @steps_dir
      step = Template.new(File.read(File.join(@steps_dir, "#{name}.yml.erb")), steps_dir: @steps_dir).render(**locals)
      step = with_if(step, locals[:if]) if locals.key?(:if)
      indent_lines(step, indent)
    end

    private

    # Stamps `if: <condition>` as the first key of every top-level step in a
    # fragment. Steps carry no `if:` of their own (they self-guard in shell), so
    # there is nothing to collide with.
    def with_if(fragment, condition)
      return fragment if condition.nil? || condition.empty?
      fragment.split(/^(?=- )/).map do |step|
        next step unless step.start_with?('- ')
        head, rest = step.split("\n", 2)
        keys_indent = head[/^\s*-\s*/].tr('-', ' ')   # align the new key with the step's other keys
        "#{head}\n#{keys_indent}if: #{condition}\n#{rest}"
      end.join
    end

    def indent_lines(text, indent)
      pad = ' ' * indent
      text.lines.map { |line| line.strip.empty? ? line : pad + line }.join.rstrip
    end
  end

  # The one machine-readable metadata convention for everything sdk-actions generates —
  # a single `# sdk-actions: {json}` comment. Used by the action generator (family +
  # version) and the workflow generator (template + ref + params). Parse it with:
  #   sed -n 's/^# sdk-actions: //p' <file> | jq
  def self.metadata_comment(fields)
    "# sdk-actions: #{JSON.generate(fields)}\n"
  end
end
