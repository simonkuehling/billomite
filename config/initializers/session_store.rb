# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_mite2billomat_session',
  :secret      => 'f537bc4284f2e7af3f6f0a16fcf2f14f742aa793895658735c12a938abf101727d8fe8a7b7b58818917e18c2fbd675d2ddec7258df101d4d06aed51c1750615b'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
