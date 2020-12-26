#!/usr/bin/env ruby
#
# read sidekiq retries and send daily summary on slack
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

abort("missing REDIS_URL environment variable.") unless ENV['REDIS_URL']
abort("missing SLACKWEBHOOK environment variable.") unless ENV['SLACKWEBHOOK']

# autovivification: create nested hash as default entry with 0 as value
current_retries = Hash.new {|h,k| h[k] = Hash.new(0)}

# scan retry count of each job in each queue in retries
retries = Sidekiq::RetrySet.new
retries.each do |job|
  # tally number of jobs that are over the retry alarm limit organized by job
  current_retries[job.item["queue"]][job.item["wrapped"]] += 1
end

if current_retries.length
  slack("Daily report on production sidekiq retries:") 
  current_retries.each do |queue,v|
    v.each do |job, count|
      slack("#{queue}: #{count} #{job}s are retried")
    end
  end
else
  slack("Daily report on production sidekiq retries found it clean.")
end

# end of file
