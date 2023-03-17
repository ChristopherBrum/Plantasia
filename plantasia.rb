# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'bcrypt'
require 'logger'
require 'pry'

require_relative 'code/database_persistence'
require_relative 'code/application_util'
require_relative 'code/pagination_util'
require_relative 'code/error_handling_and_validation'
require_relative 'code/limit'

##### Configuration #####
configure do
  enable :sessions
  set :session_secret, '31e6134533a1963ce586faa87df9a28b0ea24efaf66c526b1fe9277de2f05218f2cd5b631ff1874313df0b9245ae55528f1055dfc84ac8fe75d4c8d32775a2fa'
  set :erb, escape_html: true
end

configure(:development) do
  require 'sinatra/reloader'
  also_reload 'code/database_persistence.rb'
  also_reload 'code/application_util.rb'
  also_reload 'code/pagination_util.rb'
  also_reload 'code/error_handling_and_validation.rb'
  also_reload 'code/limit.rb'
end

##### Helpers #####
helpers ApplicationUtil, PaginationUtil

##### Before #####
before do
  @storage = DatabasePersistence.new(logger)
  @current_username = session[:username]
end

##### Routes Home #####
get '/' do
  if user_signed_in?
    redirect '/discussions/1'
  else
    erb :home, layout: :layout_no_btn
  end
end

not_found do
  session[:error] = 'Invalid URL.'
  redirect '/discussions/1'
end

##### Sign in/Out #####
# Loads the sign in/sign up page
get '/users/sign_in' do
  erb :sign_in
end

# Signs in an existing user
post '/users/sign_in' do
  username_attempt = params[:username_sign_in].strip
  password_attempt = params[:password_sign_in].strip

  username_error = error_for_short_input?(username_attempt, 'username')
  password_error = error_for_password?(password_attempt)

  if username_error
    session[:error] = username_error
    status 422
    erb :sign_in
  elsif password_error
    session[:error] = password_error
    status 422
    erb :sign_in
  elsif valid_credentials?(username_attempt, password_attempt)
    session[:username] = username_attempt
    session[:success] = "Welcome back, #{username_attempt}!"
    choose_path
  else
    session[:error] = 'Invalid username or password.'
    status 422
    erb :sign_in
  end
end

# Creates a new user and logs them in
post '/users/sign_up' do
  username = params[:username_new].strip
  password = params[:password_new].strip
  retyped_password = params[:retyped_password].strip

  unauthorized_username_char = error_unauthorized_char?(username)
  unauthorized_password_char = error_unauthorized_char?(password)
  username_error = error_for_short_input?(username, 'username')
  existing_username_error = error_for_existing_username?(username)
  password_error = error_for_password?(password, retyped_password)

  if unauthorized_username_char || unauthorized_password_char
    session[:error] = 'Unauthorized character in username or password.'
    status 422
    erb :sign_in
  elsif username_error
    session[:error] = username_error
    status 422
    erb :sign_in
  elsif existing_username_error
    session[:error] = existing_username_error
    status 422
    erb :sign_in
  elsif password_error
    session[:error] = password_error
    status 422
    erb :sign_in
  else
    encrypted_password = BCrypt::Password.create(password)
    @storage.create_user(username, encrypted_password)
    session[:username] = username
    session[:success] = "Welcome to Plantasia, #{username}!"
    redirect '/'
  end
end

# Logs out the current user.
post '/users/sign_out' do
  session.delete(:username)
  session[:success] = 'You have been signed out.'
  redirect '/'
end

##### Discussions #####
# Loads the page to create a new discussion
get '/discussions/create' do
  require_signed_in_user
  erb :new_discussion
end

# Loads the page to view a page of discussions (6 per page)
get '/discussions/:page_id' do
  discussion_id_invalid = error_with_id?(params[:page_id])
  @page_id = params[:page_id].to_i
  @num_of_pages = @storage.discussion_page_total
  error = error_page_not_found?(@page_id, @num_of_pages)

  if discussion_id_invalid 
    session[:error] = "Invalid URL."
    status 422
    redirect '/discussions/1'
  elsif error
    session[:error] = error
    status 422
    redirect '/discussions/1'
  else
    @discussions = @storage.fetch_discussions(@page_id)
    erb :discussions
  end
end

# Creates a new discussion
post '/discussions/create' do
  require_signed_in_user
  title = params[:title].strip
  description = params[:description].strip

  title_error = error_for_short_input?(title, 'headline')
  description_error = error_for_long_input?(description, 'description')

  if title_error
    session[:error] = title_error
    status 422
    erb :new_discussion
  elsif description_error
    session[:error] = description_error
    status 422
    erb :new_discussion
  else
    user_id = @storage.fetch_user_id(session[:username])
    @storage.create_discussion(title, description, user_id)
    session[:success] = 'Your discussion has been added.'
    redirect '/discussions/1'
  end
end

# Loads page to update an existing discussion
get '/discussion/:discussion_id/update' do
  require_signed_in_user
  discussion_id_invalid = error_with_id?(params[:discussion_id])
  discussion_id = params[:discussion_id].to_i
  permission_error = discussion_permission?(discussion_id)
  error = error_discussion_not_found?(discussion_id)

  if permission_error
    session[:error] = permission_error
    status 422
    redirect '/discussions/1'
  elsif discussion_id_invalid 
    session[:error] = "Invalid URL."
    status 422
    redirect '/discussions/1'
  elsif error
    session[:error] = error
    status 404
    redirect '/discussions/1'
  else
    @discussion = @storage.fetch_discussion(discussion_id)
    erb :update_discussion
  end
end

# Updates a specific discussion
# Only the user who created the discussion can update it
post '/discussion/:discussion_id/update' do
  discussion_id = params[:discussion_id].to_i
  title = params[:title].strip
  description = params[:description].strip

  title_error = error_for_short_input?(title, 'headline')
  description_error = error_for_long_input?(description, 'description')

  if title_error
    session[:error] = title_error
    status 422
    redirect "/discussion/#{discussion_id}/update"
  elsif description_error
    session[:error] = description_error
    status 422
    redirect "/discussion/#{discussion_id}/update"
  else
    @storage.update_discussion(title, description, discussion_id)
    session[:success] = 'Discussion updated successfully.'
    redirect '/discussions/1'
  end
end

# Deletes a specific discussion
# Only the user who created the discussion and an admin can delete it
post '/discussion/:discussion_id/destroy' do
  discussion_id = params[:discussion_id].to_i
  error = error_discussion_not_found?(discussion_id)

  if error
    session[:error] = error
    status 404
  else
    @storage.delete_discussion(discussion_id)
    session[:success] = 'The discussion has been deleted.'
  end
  redirect '/discussions/1'
end

##### Comments #####
get '/discussion/:discussion_id/comments/create' do
  require_signed_in_user
  discussion_id = params[:discussion_id].to_i
  redirect "/discussion/#{discussion_id}/comments/1"
end

# Displays comments of a specific dicussion
get '/discussion/:discussion_id/comments/:page_id' do
  discussion_id_invalid = error_with_id?(params[:discussion_id])
  page_id_invalid = error_with_id?(params[:page_id])
  @discussion_id = params[:discussion_id].to_i
  @page_id = params[:page_id].to_i
  @num_of_pages = @storage.comment_page_total(@discussion_id).to_i

  discussion_error = error_discussion_not_found?(@discussion_id)
  comment_page_error = error_page_not_found?(@page_id, @num_of_pages)

  if discussion_id_invalid || page_id_invalid
    session[:error] = "Invalid URL."
    status 422
    redirect '/discussions/1'
  elsif discussion_error
    session[:error] = discussion_error
    status 404
    redirect '/discussions/1'
  elsif comment_page_error
    session[:error] = comment_page_error
    status 404
    redirect "/discussion/#{@discussion_id}/comments/1"
  else
    @discussion = @storage.fetch_discussion(@discussion_id)
    @comments = @storage.fetch_comments(@discussion_id, @page_id)
    erb :comments
  end
end

# Create a new comment on a specific dicussion
post '/discussion/:discussion_id/comments/create' do
  require_signed_in_user
  comment = params[:comment].strip
  discussion_id = params[:discussion_id].to_i
  comment_error = error_for_long_input?(comment, 'comment')

  if comment_error
    session[:error] = comment_error
    status 422
  else
    user_id = @storage.fetch_user_id(session[:username])
    @storage.create_comment(discussion_id, user_id, comment)
    session[:success] = 'Your comment was created'
  end
  redirect "/discussion/#{discussion_id}/comments/1"
end

# Delete a comment on a specific dicussion
post '/discussion/:discussion_id/comment/:comment_id/destroy' do
  discussion_id = params[:discussion_id].to_i
  comment_id = params[:comment_id].to_i

  discussion_error = error_discussion_not_found?(discussion_id)
  comment_error = error_comment_not_found?(comment_id)
  comment_not_in_discussion_error = error_comment_not_in_discussion?(discussion_id, comment_id)

  if discussion_error
    session[:error] = discussion_error
    status 404
  elsif comment_error
    session[:error] = comment_error
    status 404
  elsif comment_not_in_discussion_error
    session[:error] = comment_not_in_discussion_error
    status 422
  else
    @storage.delete_comment(discussion_id, comment_id)
    session[:success] = 'Comment successfully deleted.'
  end
  redirect "/discussion/#{discussion_id}/comments/1"
end

# Loads the page to update a comment
get '/discussion/:discussion_id/comment/:comment_id/update' do
  require_signed_in_user
  discussion_id_invalid = error_with_id?(params[:discussion_id])
  page_id_invalid = error_with_id?(params[:comment_id])
  @discussion_id = params[:discussion_id].to_i
  @comment_id = params[:comment_id].to_i

  permission_error = comment_permission?(@comment_id)
  discussion_error = error_discussion_not_found?(@discussion_id)
  comment_error = error_comment_not_found?(@comment_id)
  comment_not_in_discussion_error = error_comment_not_in_discussion?(@discussion_id, @comment_id)

  if permission_error
    session[:error] = permission_error
    status 422
    redirect '/discussions/1'
  elsif discussion_id_invalid || page_id_invalid
    session[:error] = "Invalid URL."
    status 422
    redirect '/discussions/1'
  elsif discussion_error
    session[:error] = discussion_error
    status 404
    redirect "/discussion/#{@discussion_id}/comments/1"
  elsif comment_error
    session[:error] = comment_error
    status 404
    redirect "/discussion/#{@discussion_id}/comments/1"
  elsif comment_not_in_discussion_error
    session[:error] = comment_not_in_discussion_error
    status 422
    redirect "/discussion/#{@discussion_id}/comments/1"
  else
    @comment = @storage.fetch_comment(@comment_id)
    erb :update_comment
  end
end

# Update a comment on a specific dicussion
# Only the user who created the comment can edit it
post '/discussion/:discussion_id/comment/:comment_id/update' do
  @discussion_id = params[:discussion_id].to_i
  @comment_id = params[:comment_id].to_i
  comment = params[:comment].strip

  discussion_error = error_discussion_not_found?(@discussion_id)
  comment_error = error_comment_not_found?(@comment_id)
  comment_not_in_discussion_error = error_comment_not_in_discussion?(@discussion_id, @comment_id)
  comment_length_error = error_for_long_input?(comment, "comment")

  if discussion_error
    session[:error] = discussion_error
    status 404
  elsif comment_error
    session[:error] = comment_error
    status 404
  elsif comment_not_in_discussion_error
    session[:error] = comment_not_in_discussion_error
    status 422
  elsif comment_length_error
    session[:error] = comment_length_error
    status 422
    redirect "/discussion/#{@discussion_id}/comment/#{@comment_id}/update"
  else
    @storage.update_comment(@comment_id, comment)
    session[:success] = 'Comment has been updated.'
  end
  redirect "/discussion/#{@discussion_id}/comments/1"
end
