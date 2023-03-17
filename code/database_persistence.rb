# frozen_string_literal: true

require 'pg'

# DatabasePersistence controls all query interactions with the database 'plantasia'
class DatabasePersistence
  def initialize(logger)
    @db = PG.connect(dbname: 'plantasia')
    @logger = logger
  end

  def query(statement, *params)
    @logger.info "\n\n-->params: \n#{params}\n\n-->statement: \n#{statement}\n"
    @db.exec_params(statement, params)
  end

  # User Login Statements
  def all_usernames
    result = query('SELECT username FROM users')
    result.map do |tuple|
      { username: tuple['username'] }
    end
  end

  def fetch_user_credentials(username)
    sql = 'SELECT id, username, password FROM users WHERE username LIKE $1'
    result = query(sql, username)
    tuple = result.first

    return nil if tuple.nil?

    { username: tuple['username'],
      password: tuple['password'] }
  end

  def fetch_username(discussion_id)
    sql = <<~SQL
      SELECT username FROM users AS u
        JOIN discussions AS d
          ON d.user_id = u.id
        WHERE d.id = $1;
    SQL

    result = query(sql, discussion_id)
    result.first['username']
  end

  def fetch_user_id(username)
    sql = 'SELECT id FROM users WHERE username LIKE $1'
    result = query(sql, username)
    result.first['id']
  end

  def create_user(username, password)
    sql = 'INSERT INTO users (username, password) VALUES ($1, $2)'
    query(sql, username, password)
  end

  def user_is_admin?(username)
    sql = 'SELECT admin FROM users WHERE username LIKE $1'
    result = query(sql, username)
    result.first['admin'] if result.first
  end

  # Discussions Statements
  def fetch_discussions(page_id = 1)
    sql = <<~SQL
      SELECT d.id,
             d.title,
             d.description,
             d.user_id,
             TO_CHAR(d.date_created :: DATE, 'mm/dd/yyyy') AS date_created,
             TO_CHAR(d.time_created :: TIME, 'HH24:MI') AS time_created,
             u.username AS username
        FROM discussions AS d
        JOIN users AS u
          ON d.user_id = u.id
        ORDER BY date_created DESC, time_created DESC
        LIMIT #{Limits::DISCUSSION_PAGES}
        OFFSET (($1 - 1) * #{Limits::DISCUSSION_PAGES});
    SQL

    result = query(sql, page_id)
    result.map do |tuple|
      { id: tuple['id'],
        title: tuple['title'],
        description: tuple['description'],
        user_id: tuple['user_id'],
        date_created: tuple['date_created'],
        time_created: tuple['time_created'],
        username: tuple['username'],
        comment_count: tuple['comment_count'] }
    end
  end

  def fetch_discussion(discussion_id)
    sql = 'SELECT * FROM discussions WHERE id = $1'
    result = query(sql, discussion_id)
    tuple = result.first

    { id: tuple['id'],
      title: tuple['title'],
      description: tuple['description'],
      date_created: tuple['date_created'],
      time_created: tuple['time_created'],
      user_id: tuple['user_id'] }
  end

  def discussion_page_total
    sql = "SELECT CEIL((COUNT(id)::float / #{Limits::DISCUSSION_PAGES})) AS total_pages FROM discussions;"
    result = query(sql)
    result.first['total_pages'].to_i
  end

  def discussion_comment_total(discussion_id)
    sql = 'SELECT COUNT(id) FROM comments WHERE discussion_id = $1'
    result = query(sql, discussion_id)
    result.first['count']
  end

  def discussion_exists?(discussion_id)
    sql = 'SELECT id FROM discussions WHERE id = $1'
    result = query(sql, discussion_id)
    id = result.first
    return id if id
  end

  def create_discussion(title, description, user_id)
    sql = <<~SQL
      INSERT INTO discussions#{' '}
        (title, description, user_id)
      VALUES
        ($1, $2, $3)
    SQL

    query(sql, title, description, user_id)
  end

  def update_discussion(title, description, discussion_id)
    sql = <<~SQL
      UPDATE discussions
         SET title = $1, description = $2
         WHERE id = $3;
    SQL

    query(sql, title, description, discussion_id)
  end

  def delete_discussion(discussion_id)
    sql = 'DELETE FROM discussions WHERE id = $1'
    query(sql, discussion_id)
  end

  def fetch_discussion_user_id(discussion_id)
    sql = "SELECT user_id FROM discussions WHERE id = $1"

    result = query(sql, discussion_id)
    result.first["user_id"] if result.first
  end

  # Comments Statements
  def fetch_comments(discussion_id, page_id = 1)
    sql = <<~SQL
      SELECT c.id,
             c.discussion_id,
             c.user_id,
             c.comment,
             TO_CHAR(c.date_created :: DATE, 'mm/dd/yyyy') AS date_created,
             TO_CHAR(c.time_created :: TIME, 'HH24:MI:SS') AS time_created,
             u.username
        FROM comments AS c
        JOIN users AS u
        ON c.user_id = u.id
        WHERE c.discussion_id = $1
        ORDER BY date_created DESC, time_created DESC
        LIMIT $2
        OFFSET (($3 - 1) * $4);
    SQL

    limit = Limits::COMMENT_PAGES
    result = query(sql, discussion_id, limit, page_id, limit)

    result.map do |tuple|
      { id: tuple['id'],
        discussion_id: tuple['discussion_id'],
        user_id: tuple['user_id'],
        comment: tuple['comment'],
        date_created: tuple['date_created'],
        time_created: tuple['time_created'],
        username: tuple['username'] }
    end
  end

  def fetch_comment(comment_id)
    sql = 'SELECT comment FROM comments WHERE id = $1'
    result = query(sql, comment_id)
    result.first['comment']
  end

  def update_comment(comment_id, comment)
    sql = <<~SQL
      UPDATE comments
         SET comment = $1,#{' '}
             date_created = now(),#{' '}
             time_created = now()
         WHERE id = $2
    SQL

    query(sql, comment, comment_id)
  end

  def comment_page_total(discussion_id)
    sql = <<~SQL
      SELECT CEIL((COUNT(id)::float / $1)) AS total_pages#{' '}
        FROM comments#{' '}
        WHERE discussion_id = $2
    SQL

    result = query(sql, Limits::COMMENT_PAGES, discussion_id)
    result.first['total_pages'].to_i
  end

  def create_comment(discussion_id, user_id, comment)
    sql = <<~SQL
      INSERT INTO comments#{' '}
        (discussion_id, user_id, comment)
      VALUES#{' '}
        ($1, $2, $3);
    SQL

    query(sql, discussion_id, user_id, comment)
  end

  def comment_exists?(comment_id)
    sql = 'SELECT id FROM comments WHERE id = $1'

    result = query(sql, comment_id)
    id = result.first
    return id if id
  end

  def comment_exists_in_discussion?(discussion_id, comment_id)
    sql = <<~SQL
      SELECT d.id#{' '}
      FROM discussions AS d#{' '}
      JOIN comments AS c#{' '}
        ON d.id = c.discussion_id#{' '}
        WHERE d.id = $1 AND c.id = $2;
    SQL

    result = query(sql, discussion_id, comment_id)
    id = result.first
    return id if id
  end

  def comment_count(discussion_id)
    sql = 'SELECT count(id) FROM comments WHERE discussion_id = $1'
    result = query(sql, discussion_id)
    result.first['count']
  end

  def fetch_comment_user_id(comment_id)
    sql = "SELECT user_id FROM comments WHERE id = $1"

    result = query(sql, comment_id)
    result.first["user_id"] if result.first
  end

  def delete_comment(discussion_id, comment_id)
    sql = <<~SQL
      DELETE FROM comments#{' '}
       WHERE discussion_id = $1
         AND id = $2
    SQL

    query(sql, discussion_id, comment_id)
  end
end
