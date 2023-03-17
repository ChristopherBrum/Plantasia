# bundle install # toggle on/off as needed

DATABASE=$1

dropdb $DATABASE
createdb $DATABASE

psql -d $DATABASE < schema.sql
psql -d $DATABASE < seed_data.sql

bundle exec ruby plantasia.rb

# run this command: bash db_restore.sh plantasia