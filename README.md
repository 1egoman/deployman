# deployman [![Build Status](https://secure.travis-ci.org/1egoman/deployman.png?branch=master)](http://travis-ci.org/1egoman/deployman)

Like Heroku. Better than Dokku. Free/Open Source. So, yea, give it a try.

# Setup Nginx
```bash
sudo apt-get install nginx
sudo curl https://gist.githubusercontent.com/1egoman/aa2cc593e9504980130f/raw/1f89e91bd5874023035bdc29ef20da96dab0e54a/deployman_nginx_server.conf > /etc/nginx/sites-available/default
sudo service nginx restart
```
# Setup Deployman
```bash
# get the code
git clone https://github.com/1egoman/deployman.git
cd deployman

# update in file deployman your ROOT_TOKEN and other startup stuff

# create an init.d or upstart job
sudo cp deployman /etc/init.d/deployman
sudo chmod +x /etc/init.d/deployman
sudo update-rc.d deployman default

# give it a start
sudo service deployman start
# or
sudo /etc/init.d/deployman start
```

# Add new projects to config.json
- `cp config.example.json config.json`

```json
{
  "name": "app_name",
  "anonRead": false,
  "users": [
    {
      "user": {
        "username": "your_username",
        "password": "your_password"
      },
      "permissions": ["R", "W"]
    }
  ]
}
```
# Download the deployman client
```
npm install -g deployman-tool
dman --help
```

# Sample nginx config
<https://gist.github.com/1egoman/aa2cc593e9504980130f>

## Contributing
In lieu of a formal styleguide, take care to maintain the existing coding style. Add unit tests for any new or changed functionality. Lint and test your code using [Grunt](http://gruntjs.com/).

## License
Copyright (c) 2015 Ryan Gaus. Licensed under the MIT license.
