require 'sinatra'
require "sinatra/reloader" if development?
require 'httparty'

get '/' do
  haml :index
end

post '/transcript' do
  auth = { username: params[:auth][:user], password: params[:auth][:token] }

  # get conversation id
  if params[:conversation_id].empty? && !params[:conversation_item_id].empty?
    url = "https://#{params[:auth][:env]}/api/v1/conversation-items/#{params[:conversation_item_id]}"
    response = HTTParty.get url, :basic_auth => auth
    conversation_id = response.parsed_response["conversationId"]
    conversation_id
  else
    conversation_id = params[:conversation_id]
  end


  # get transcript
  url = "https://#{params[:auth][:env]}/api/v1/conversations/#{conversation_id}/items"
  response = HTTParty.get url, :basic_auth => auth
  raw_items = response.parsed_response
  raw_items.reject! { |c| !c["initiator"] || c["initiator"]["type"] == "API" || c["initiator"]["type"] == "AUTOMATION" }

  # get agents
  agent_ids = raw_items.collect do |c|
    if c["initiator"]["type"] == "AGENT"
      c["initiator"]["id"]
    else
      nil
    end
  end.compact.uniq

  agents = {}
  agent_ids.each do |a|
    url = "https://#{params[:auth][:env]}/api/v1/agents/#{a}"
    response = HTTParty.get url, :basic_auth => auth
    agent = response.parsed_response
    agents[agent["id"]] = agent
  end

  # get customer
  customer_id = raw_items.first["customerId"]
  url = "https://#{params[:auth][:env]}/api/v1/customer-profiles/#{customer_id}"
  response = HTTParty.get url, :basic_auth => auth
  customer = response.parsed_response
  customer_link = "https://#{params[:auth][:env]}/customer/#{customer_id}"

  # process items
  items = []
  raw_items.each do |item|
    i = {
        created_at: Time.parse(item["timestamp"]).strftime("%A, %d %b %Y %l:%M %p"),
        content: item["content"]["content"]
      }

    if item["initiator"]["type"] == "AGENT"
      i[:creator] = agents[item["initiator"]["id"]]["name"]
      i[:direction] = :out
    else
      i[:creator] = customer["name"]
      i[:direction] = :in
    end

    i[:channel] = case item["content"]["type"]
    when "CHAT_MESSAGE"     then "Sent a chat message"
    when "EMAIL"            then "Sent an email"
    when "FACEBOOK_MESSAGE" then "Sent a Facebook message"
    when "SMS"              then "Sent a text message"
    when "PHONE_CALL"       then "Called"
    end

    items << i unless i[:channel].nil?
  end

  @transcript = {
    agents: agents,
    customer: customer,
    customer_link: customer_link,
    items: items,
    link: "#{customer_link}/item/#{items.first["id"]}",
    started_at: items.first[:created_at]
  }

  haml :transcript
end