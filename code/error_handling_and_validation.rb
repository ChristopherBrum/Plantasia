# frozen_string_literal: true

def require_signed_in_user
  return if user_signed_in?

  session[:error] = 'You must be signed in to do that.'
  session[:path] = request.path_info
  redirect '/users/sign_in'
end

def valid_credentials?(username_attempt, password_attempt)
  credentials = @storage.fetch_user_credentials(username_attempt)

  if credentials.nil? ||
     credentials[:username].nil? ||
     credentials[:password].nil?
  else
    BCrypt::Password.new(credentials[:password]) == password_attempt
  end
end

def discussion_permission?(discussion_id)
  given_user_id = @storage.fetch_user_id(session[:username])
  actual_user_id = @storage.fetch_discussion_user_id(discussion_id)
  return if given_user_id == actual_user_id

  "You do not have permission to do that."
end

def comment_permission?(comment_id)
  given_user_id = @storage.fetch_user_id(session[:username])
  actual_user_id = @storage.fetch_comment_user_id(comment_id)
  return if given_user_id == actual_user_id

  "You do not have permission to do that."
end


def error_with_id?(string)
  integers = ('0'..'9').to_a
  !string.chars.all? { |char| integers.include?(char) }
end

def choose_path
  if session.key?(:path)
    redirect session.delete(:path)
  else
    redirect '/'
  end
end

def error_unauthorized_char?(input)
  input.match?(%r{[<>/]})
end

def error_for_existing_username?(username)
  return unless @storage.all_usernames.any? { |existing_user| username == existing_user[:username] }

  'Username already exists.'
end

def error_for_password?(password, retyped_password = nil)
  if !(1..100).cover?(password.size)
    'Password must be between 1 and 100 characters long.'
  elsif !retyped_password.nil? && password != retyped_password
    'Passwords must match.'
  end
end

def error_page_not_found?(page_id, num_of_pages)
  return if num_of_pages.zero?
  return if (1..num_of_pages).cover?(page_id)

  'That page does not exist.'
end

def error_for_short_input?(input, name)
  return if (1..100).cover?(input.size)

  "#{name.capitalize} must be between 1 and 100 characters long."
end

def error_for_long_input?(input, name)
  return if (1..1000).cover?(input.size)

  "#{name.capitalize} must be between 1 and 1000 characters long."
end

def error_discussion_not_found?(discussion_id)
  return if @storage.discussion_exists?(discussion_id)

  'Not a valid discussion id.'
end

def error_comment_not_found?(discussion_id)
  return if @storage.comment_exists?(discussion_id)

  'Not a valid comment id.'
end

def error_comment_not_in_discussion?(discussion_id, comment_id)
  return if @storage.comment_exists_in_discussion?(discussion_id, comment_id)

  'Comment is not part of this discussion.'
end
