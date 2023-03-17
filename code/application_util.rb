# frozen_string_literal: true

# Module for application methods utilized within routes
module ApplicationUtil
  def comment_count(discussion_id)
    @storage.comment_count(discussion_id)
  end

  def discussion_author(discussion_id)
    @storage.fetch_username(discussion_id)
  end

  def users_post?(user_id)
    @storage.fetch_user_id(@current_username).to_i == user_id
  end

  def user_signed_in?
    session.key?(:username)
  end

  def admin?(username)
    true if @storage.user_is_admin?(username) == 't'
  end
end
