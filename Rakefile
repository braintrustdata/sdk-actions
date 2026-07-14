ACTIONS       = FileList['actions/**/action.yml']
ACTION_SCHEMA = 'scripts/github-action.schema.json'

# Golden workflow fixtures: bt-publishing-test's release workflows, generated into a
# mirrored consumer-repo layout under test/release/<lang>/. Regenerated + drift-guarded
# (like actions/) so a template change can't land without its rendered output updating.
# `ref` is a fixed real sdk-actions commit so fixtures stay stable across regenerations
# (fixtures never run — only the repo-root .github/workflows/ does); bump it deliberately.
WORKFLOW_REF = '38dcec863c910f6802c03a94ab9aeb79931a0a3a'
WORKFLOW_FIXTURES = [
  { id: 'release/ruby/turnkey', dest: 'test/release/ruby/.github/workflows/release.yml',
    args: %w[--gem-name bt-publishing-test --version-module BtPublishingTest] },
  { id: 'release/ruby/custom', dest: 'test/release/ruby/.github/workflows/release-custom.yml',
    args: %w[--gem-name bt-publishing-test --version-module BtPublishingTest] },
  { id: 'release/py/turnkey', dest: 'test/release/py/.github/workflows/release.yml',
    args: %w[--package-name bt-publishing-test] },
  { id: 'release/py/custom', dest: 'test/release/py/.github/workflows/release-custom.yml',
    args: %w[--package-name bt-publishing-test] },
  { id: 'release/js/turnkey', dest: 'test/release/js/.github/workflows/release.yml',
    args: %w[--package-name @braintrust/bt-publishing-test] },
  { id: 'release/js/custom', dest: 'test/release/js/.github/workflows/release-custom.yml',
    args: %w[--package-name @braintrust/bt-publishing-test] },
].freeze

task default: :ci

desc 'All CI checks (actions + workflows)'
task ci: %w[actions:ci workflows:ci]

def yaml_errors(files)
  require 'yaml'
  files.sort.filter_map do |file|
    YAML.safe_load_file(file)
    nil
  rescue Psych::SyntaxError => e
    "  #{file}:#{e.line}:#{e.column}: #{e.problem}"
  end
end

def check_jsonschema!
  on_path = ENV['PATH'].to_s.split(File::PATH_SEPARATOR)
                       .any? { |dir| File.executable?(File.join(dir, 'check-jsonschema')) }
  return if on_path
  abort <<~MSG.strip
    check-jsonschema not found on PATH. Install the toolchain with `mise install`
    (or `pipx install check-jsonschema`), then re-run.
  MSG
end

namespace :actions do
  desc 'Render actions/ from templates/actions/'
  task :generate do
    ruby 'scripts/generate.rb'
  end

  desc 'Validate generated actions (YAML + GitHub Action schema)'
  task :validate do
    errors = yaml_errors(ACTIONS)
    abort "Malformed YAML in generated actions:\n#{errors.join("\n")}" unless errors.empty?
    check_jsonschema!
    sh 'check-jsonschema', '--schemafile', ACTION_SCHEMA, *ACTIONS
  end

  desc 'CI guard: regenerate + validate, then fail if committed actions/ drifted'
  task ci: %w[actions:generate actions:validate] do
    sh 'git', 'diff', '--exit-code', 'actions/'
  end
end

namespace :workflows do
  desc 'Regenerate the golden workflow fixtures from templates/workflows/'
  task :generate do
    WORKFLOW_FIXTURES.each do |f|
      sh 'bin/workflow', 'generate', f[:id], *f[:args], '--ref', WORKFLOW_REF, '--dest', f[:dest], '--force'
    end
  end

  desc 'Validate the golden workflow fixtures (delegates to `bin/workflow validate`)'
  task :validate do
    WORKFLOW_FIXTURES.each { |f| sh 'bin/workflow', 'validate', f[:dest] }
  end

  desc 'CI guard: regenerate + validate, then fail if committed fixtures drifted'
  task ci: %w[workflows:generate workflows:validate] do
    sh 'git', 'diff', '--exit-code', *WORKFLOW_FIXTURES.map { |f| f[:dest] }
  end
end
