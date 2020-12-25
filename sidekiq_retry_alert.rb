#!/usr/bin/env ruby
#
# read sidekiq retries and report jobs on slack that keep failing
#
# imre Fitos, 2020
require 'csv'
require 'net/https'
require 'sidekiq/api'
require 'uri'

def slack(msg)
  p msg
  uri = URI.parse(ENV["SLACKWEBHOOK"])
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri)
  request.body = {text: msg}.to_json
  request.content_type = "application/json"
  response = http.request(request)
  case response
    when Net::HTTPSuccess
      p "Sent successfully"
    else
      {'error' => response.message}
  end
end

abort("Usage: #{$0} state-file retry-limit") unless ARGV[1]
abort("Usage: #{$0} state-file retry-limit.\nretry-limit has to be an integer") unless limit = Integer(ARGV[1], exception:false)
abort("missing REDIS_URL environment variable.") unless ENV['REDIS_URL']
abort("missing SLACKWEBHOOK environment variable.") unless ENV['SLACKWEBHOOK']

if not File.exist?(ARGV[0])
    File::new(ARGV[0], File::CREAT, 0600)
end

past_retries = CSV.read(ARGV[0], converters: :integer)

# autovivification: create nested hash as default entry with 0 as value
current_retries = Hash.new {|h,k| h[k] = Hash.new(0)}

# scan retry count of each job in each queue in retries
retries = Sidekiq::RetrySet.new
retries.each do |job|
  break if job.item["retry_count"] < limit
  # tally number of jobs that are over the retry alarm limit organized by job
  current_retries[job.item["queue"]][job.item["wrapped"]] += 1
end

# compare tally from last time, alert if count is higher
updated_retries = Array.new
current_retries.each do |queue,v|
  v.each do |job, count|
    found = past_retries.find_index { |row| row[0] == queue and row[1] == job}
    if (found and (past_retries[found][2] < count)) or not found
      slack("PRODUCTION ALARM: #{count} #{job}s on the #{queue} queue have failed #{ARGV[1]}+ times")
    end
    # save the count for the next time to reset high water mark
    # array format for CSV convenience
    updated_retries.push([queue, job, count])
  end
end

# save current state
CSV.open(ARGV[0], "wb") do |csv|
  updated_retries.each do |row|
    csv << row
  end
end
# end of file
