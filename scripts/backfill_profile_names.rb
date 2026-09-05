# Run with bin/rails runner scripts/backfill_profile_names.rb after migrating.
# Before rolling back the schema, run the same script with the argument restore.
mode = ARGV.first || "split"
updated = 0

case mode
when "split"
  Dependent.where(first_name: nil, last_name: nil).find_each do |profile|
    first_name, last_name = profile.legacy_name.to_s.strip.split(/\s+/, 2)
    next if first_name.blank?

    updated += Dependent.where(id: profile.id, first_name: nil, last_name: nil, legacy_name: profile.legacy_name)
      .update_all(first_name: first_name, last_name: last_name)
  end

  puts "Backfilled #{updated} profile names."
  remaining = Dependent.where(first_name: nil).count
  abort "#{remaining} profiles still need a first name; review their original names before continuing." if remaining.positive?
when "restore"
  Dependent.find_each do |profile|
    updated += Dependent.where(id: profile.id, first_name: profile.first_name, last_name: profile.last_name)
      .update_all(legacy_name: profile.name)
  end

  puts "Prepared #{updated} profile names for schema rollback."
else
  abort "Usage: bin/rails runner scripts/backfill_profile_names.rb [split|restore]"
end
