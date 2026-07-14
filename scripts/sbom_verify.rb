#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Verify a CycloneDX SBOM against the package-SBOM spec — not just that it's valid JSON,
# but that it describes the released package correctly. Guards the SBOM generators
# (templates/steps/**/sbom*.yml.erb) against silent content regressions.
#
# Structural invariants (always enforced):
#   - bomFormat == "CycloneDX", plus specVersion + serialNumber present
#     (actions/attest requires all three to recognize the SBOM as CycloneDX).
#   - a metadata.component SUBJECT with name, version, purl, and bom-ref.
#   - a dependencies graph rooted at the subject's bom-ref (NTIA dependency relationship).
#
# Package-specific assertions (flags supplied by the caller):
#   ruby scripts/sbom_verify.rb <sbom.json> [--subject NAME] [--purl-prefix P] [--require a,b] [--forbid c,d]
#     --subject       expected metadata.component.name
#     --purl-prefix   subject purl must start with this (ecosystem + name; version-agnostic)
#     --require       component names that MUST be present (runtime deps)
#     --forbid        component names that must be ABSENT (dev/build tooling)

require 'json'
require 'optparse'

opts = { require: [], forbid: [], subject: nil, purl_prefix: nil }
parser = OptionParser.new do |o|
  o.banner = 'usage: ruby scripts/sbom_verify.rb <sbom.json> [--subject NAME] [--purl-prefix P] [--require a,b] [--forbid c,d]'
  o.on('--subject NAME',   'expected metadata.component.name') { |v| opts[:subject] = v }
  o.on('--purl-prefix P',  'subject purl must start with this (ecosystem + name)') { |v| opts[:purl_prefix] = v }
  o.on('--require LIST',   'component names that MUST be present') { |v| opts[:require] = v.split(',').map(&:strip).reject(&:empty?) }
  o.on('--forbid LIST',    'component names that must be ABSENT')  { |v| opts[:forbid]  = v.split(',').map(&:strip).reject(&:empty?) }
  o.on('-h', '--help') { puts o; exit 0 }
end
parser.parse!(ARGV)
file = ARGV.shift or abort(parser.to_s)

abort "error: no such file: #{file}" unless File.exist?(file)
begin
  sbom = JSON.parse(File.read(file))
rescue JSON::ParserError => e
  abort "error: #{file} is not valid JSON: #{e.message}"
end

errors = []

# Structural: the actions/attest recognition triple.
errors << 'bomFormat is not "CycloneDX"' unless sbom['bomFormat'] == 'CycloneDX'
errors << 'specVersion is missing' if sbom['specVersion'].to_s.empty?
errors << 'serialNumber is missing (actions/attest will not recognize the SBOM)' if sbom['serialNumber'].to_s.empty?

# Structural: the subject (metadata.component) — a package SBOM must name its subject.
subject = sbom.dig('metadata', 'component') || {}
sref    = subject['bom-ref']
if subject.empty?
  errors << 'metadata.component (subject) is missing — this is an anonymous component list, not a package SBOM'
else
  errors << 'subject has no name'    if subject['name'].to_s.empty?
  errors << 'subject has no version' if subject['version'].to_s.empty?
  errors << 'subject has no purl'    if subject['purl'].to_s.empty?
  errors << 'subject has no bom-ref' if sref.to_s.empty?
end

# Structural: a dependency graph rooted at the subject.
deps = sbom['dependencies']
if !deps.is_a?(Array) || deps.empty?
  errors << 'no dependencies graph (NTIA dependency-relationship element)'
elsif !sref.to_s.empty? && deps.none? { |d| d['ref'] == sref }
  errors << "dependencies graph has no root entry for the subject (ref #{sref.inspect})"
end

# Package-specific assertions.
components = Array(sbom['components']).filter_map { |c| c['name'] }
present    = ([subject['name']] + components).compact
errors << "subject name is #{subject['name'].inspect}, expected #{opts[:subject].inspect}" if opts[:subject] && subject['name'] != opts[:subject]
if opts[:purl_prefix] && !subject['purl'].to_s.start_with?(opts[:purl_prefix])
  errors << "subject purl #{subject['purl'].inspect} does not start with #{opts[:purl_prefix].inspect}"
end
opts[:require].each { |n| errors << "required component #{n.inspect} is missing" unless present.include?(n) }
opts[:forbid].each  { |n| errors << "forbidden component #{n.inspect} is present — dev/build tooling leaked into the SBOM" if present.include?(n) }

if errors.empty?
  puts "ok — #{file}: subject=#{subject['name'].inspect} (#{subject['purl']}), #{components.size} runtime component(s)"
else
  warn "SBOM content check failed for #{file}:"
  errors.each { |e| warn "  - #{e}" }
  warn "  subject: #{subject['name'].inspect} purl=#{subject['purl'].inspect}"
  warn "  components: #{components.sort.inspect}"
  exit 1
end
