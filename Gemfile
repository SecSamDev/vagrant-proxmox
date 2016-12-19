source 'https://rubygems.org'

gemspec

group :development do
  # We depend on Vagrant for development, but we don't add it as a
  # gem dependency because we expect to be installed within the
  # Vagrant environment itself using `vagrant plugin`.
  gem 'vagrant', '1.9.1',
      git: 'https://github.com/mitchellh/vagrant.git',
      ref: 'v1.9.1'
end
