namespace :rules do
  desc "Index rules from a CSV into sqlite-vec. Usage: rake rules:index CSV=/path/to/file.csv"
  task index: :environment do
    RuleIndexer.index_csv(ENV.fetch("CSV"))
  end
end
