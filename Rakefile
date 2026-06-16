ACTIONS  = FileList['actions/**/action.yml']
SCHEMA   = 'scripts/github-action.schema.json'

task default: :generate

desc 'Render actions/ from templates/, then validate them (YAML + schema)'
task generate: %i[render validate]

desc 'Render actions/ from templates/ (no validation)'
task :render do
  ruby 'scripts/generate.rb'
end

desc 'Run all checks on the generated actions (YAML + schema)'
task validate: %w[validate:yaml validate:schema]

namespace :validate do
  desc 'Check that every generated action parses as YAML (stdlib, no extra deps)'
  task :yaml do
    require 'yaml'
    errors = ACTIONS.sort.filter_map do |file|
      YAML.safe_load_file(file)
      nil
    rescue Psych::SyntaxError => e
      "  #{file}:#{e.line}:#{e.column}: #{e.problem}"
    end
    abort "Malformed YAML in generated actions:\n#{errors.join("\n")}" unless errors.empty?
  end

  desc 'Validate every generated action against the GitHub Action schema (needs check-jsonschema)'
  task :schema do
    on_path = ENV['PATH'].to_s.split(File::PATH_SEPARATOR)
                         .any? { |dir| File.executable?(File.join(dir, 'check-jsonschema')) }
    unless on_path
      abort <<~MSG.strip
        check-jsonschema not found on PATH. Install the toolchain with `mise install`
        (or `pipx install check-jsonschema`), then re-run. To skip schema validation,
        use `rake render` or `rake validate:yaml`.
      MSG
    end
    sh 'check-jsonschema', '--schemafile', SCHEMA, *ACTIONS
  end
end

namespace :ci do
  desc 'CI guard: regenerate + validate, then fail if committed actions/ is out of sync with templates/'
  task actions: :generate do
    sh 'git', 'diff', '--exit-code', 'actions/'
  end
end
