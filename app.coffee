# Module dependencies
express = require 'express'
_ = underscore = require 'underscore'
app = module.exports = express.createServer()


# Mongoose configuration
mongoose = require 'mongoose'
mongooseTypes = require 'mongoose-types'
mongooseTypes.loadTypes mongoose
mongoose.connect 'mongodb://localhost/l4c'
Schema = mongoose.Schema
ObjectId = Schema.ObjectId
Email = mongoose.SchemaTypes.Email
Url = mongoose.SchemaTypes.Url

UserSchema = new Schema
	_photos: [
		type: ObjectId
		ref: 'Photo'
	]
	clab: String
	created_at:
		default: Date.now
		type: Date
	email:
		lowercase: true
		required: true
		type: Email,
		unique: true
	password:
		required: true
		type: String
	username:
		lowercase: true
		required: true
		type: String
		unique: true


CommentSchema = new Schema
	_user: [
		type: ObjectId
		ref: 'User'
		required: true
	]
	body:
		type: String
		required: true
	created_at:
		default: Date.now
		type: Date


PhotoSchema = new Schema
	_tags: [
		type: ObjectId
		ref: 'Tag'
	]
	_user: [
		type: ObjectId
		ref: 'User'
		required: true
	]
	comments: [ CommentSchema ]
	created_at:
		default: Date.now
		required: true
		type: Date
	description: String
	name:
		required: true
		type: String
	sizes:
		m: String
		s: String
		o: String
	slug:
		required: true
		type: String
		unique: true
	views:
		default: 0
		type: Number


TagSchema = new Schema
	count:
		default: 0
		type: Number
	name:
		lowercase: true
		type: String
		required: true
		unique: true


Photo = mongoose.model 'Photo', PhotoSchema
Tag = mongoose.model 'Tag', TagSchema
User  = mongoose.model 'User', UserSchema


# Passport configuration
passport = require 'passport'
LocalStrategy = require('passport-local').Strategy


passport.serializeUser (user, next) ->
	next null, user.username


passport.deserializeUser (username, next) ->
	model = mongoose.model('User')
	model.findOne username: username, (err, doc) ->
		return next null, false if err
		next null, doc


passport.use new LocalStrategy (username, password, next) ->
	model = mongoose.model 'User'
	console.log 'local strategy', username, password, model
	model.findOne
			username: username
			password: password
		, (err, doc) ->
			return next err, false if err
			next null, doc


# Express configuration
app.configure ->
	app.set 'views', __dirname + '/public/templates'
	app.set 'view engine', 'jade'
	app.set 'strict routing', true

	app.use express.favicon()
	oneYear = 31556926000; # 1 year on milliseconds
	app.use express.static( __dirname + '/public', maxAge: oneYear )
	app.use express.logger( format: ':status ":method :url"' )

	app.use express.cookieParser()
	app.use express.bodyParser()
	app.use express.methodOverride()
	app.use express.session secret: '♥'

	app.use passport.initialize()
	app.use passport.session()
	
	app.use app.router


# Middleware
middleware =
	# auth: (path = '/') -> (req, res, next) ->
	# 	passport.authenticate 'local', sucessRedirect: path, failureRedirect: '/login'
	
	auth: (req, res, next) ->
		if req.isAuthenticated()
			return next()
		
		req.flash 'auth_redirect', req.originalUrl
		res.redirect('/login')
	

	hmvc: (path) -> (req, res, next) ->
		route = app.match.get(path)
		route = _.filter route, (i) -> i.path == path
		route = _.first route
		callback = _.last route.callbacks
		
		if _.isFunction callback
			callback(req, res)
		else
			next('route')
	

	paged: (path) -> (req, res, next) ->
		redirection = path.replace '?', ''
		path_vars = _.filter redirection.split('/'), (i) -> i.charAt(0) == ':'

		for path_var, i of path_vars
			redirection = redirection.replace i, req.params[ i.substring(1) ]
		
		page = parseInt req.param 'page', 1
		res.local 'page', page
		
		if page == 1
			return res.redirect redirection, 301
		
		middleware.hmvc(path)(req, res, next)
	

	remove_trailing_slash: (req, res, next) ->
		url = req.originalUrl
		length = url.length
		
		if length > 1 && url.charAt(length - 1) == '/'
			url = url.substring 0, length - 1
			return res.redirect url, 301
		
		next()


# Helpers
helpers =
	slugify: (str) ->
		str = str.replace /^\s+|\s+$/g, ''
		str = str.toLowerCase()

		# remove accents, swap ñ for n, etc
		from = "àáäâèéëêìíïîòóöôùúüûñç®©·/_,:;"
		to   = "aaaaeeeeiiiioooouuuuncrc------"

		for i, character of from.split ''
			str = str.replace new RegExp(character, 'g'), to.charAt i
		
		# trademark sign
		str = str.replace new RegExp('™', 'g'), 'tm'

		# remove invalid chars
		str = str.replace /[^a-z0-9 -]/g, ''

		# collapse whitespace and replace by -
		str = str.replace /\s+/g, '-'
		
		# collapse dashes
		str = str.replace /-+/g, '-'


# Route Params
app.param 'page', (req, res, next, id) ->
	if id.match /[0-9]+/
		req.param.page = parseInt req.param.page
		next()
	else
		return next(404)


app.param 'size', (req, res, next, id) ->
	if id in ['p', 'm', 'o']
		next()
	else
		return next('route')


app.param 'slug', (req, res, next, id) ->
	if id not in ['editar']
		next()
	else
		return next('route')


app.param 'sort', (req, res, next, id) ->
	if id in ['ultimas', 'top', 'galeria']
		next()
	else
		return next('route')


app.param 'user', (req, res, next, id) ->
	if id not in ['ultimas', 'top', 'galeria', 'pag', 'publicar']
		next()
	else
		return next('route')


# Routes
app.all '*', middleware.remove_trailing_slash, (req, res, next) ->
	res.locals
		_: underscore
		body_class: ''
		url: req.originalUrl
		user: if req.isAuthenticated() then req.user else null
		page: 1
	
	res.locals helpers
	next('route')


app.get '/', middleware.hmvc('/fotos/:sort?')


app.get '/fotos/:user/:slug', (req, res) ->
	res.locals
		body_class: 'single'
		photo:
			user: req.param 'user'
			slug: req.param 'slug'

	res.render 'gallery_single'


app.get '/fotos/:user/:slug/sizes/:size', (req, res) ->
	res.local 'body_class', 'sizes'
	res.render 'gallery_single_large'


app.get '/fotos/:user', (req, res) ->
	res.local 'body_class', 'gallery liquid'
	res.render 'gallery'


app.get '/fotos/:sort/pag/:page?', middleware.paged('/fotos/:sort?')
app.get '/fotos/ultimas', (req, res) -> res.redirect '/fotos', 301
app.get '/fotos/:sort?', (req, res, next) ->
	sort = req.param 'sort', 'ultimas'
	
	res.locals
		sort: sort
		path: "/fotos/#{sort}"
		body_class: "gallery liquid #{sort}"
	
	res.render 'gallery'


app.get '/tags/:tag/pag/:page?', middleware.paged('/tags/:tag')
app.get '/tags/:tag', (req, res) ->
	tag = req.params.tag
	page = parseInt req.param 'page', 1

	res.send "GET /tags/#{tag}/pag/#{page}", 'Content-Type': 'text/plain'


app.get '/tags', (req, res) ->
	res.send "GET /tags", 'Content-Type': 'text/plain'


app.get '/login', (req, res) ->
	if (req.isAuthenticated())
		return res.redirect '/'
	
	res.render 'login'


app.post '/login', passport.authenticate('local', failureRedirect: '/login'), (req, res) ->
	flash = req.flash('auth_redirect')
	url = if _.size flash then _.first flash else '/'
	res.redirect url


app.get '/logout', (req, res) ->
	req.logout()
	res.redirect '/'


app.get '/registro', (req, res) ->
	res.render 'register'


app.post '/registro', (req, res) ->
	d = req.body
	model = mongoose.model 'User'
	
	u = new model
	u.clab = d.clab
	u.email = d.email
	u.password = d.password
	u.username = d.username
	u.save (err) ->
		throw new Error err if err
		res.redirect "/perfil"

	# res.send "POST /registro \n #{req.body}", 'Content-Type': 'text/plain'


# Logged in user routes
app.get '/fotos/publicar', middleware.auth, (req, res) ->
	res.render 'gallery_upload'


app.post '/fotos/publicar', middleware.auth, (req, res) ->
	res.send "POST /fotos/publicar", 'Content-Type': 'text/plain'


app.get '/fotos/:user/:slug/editar', middleware.auth, (req, res) ->
	user = req.param 'user'
	slug = req.param 'slug'
	res.send "PUT /fotos/#{user}/#{slug}/editar", 'Content-Type': 'text/plain'


app.put '/fotos/:user/:slug', middleware.auth, (req, res) ->
	user = req.param 'user'
	slug = req.param 'slug'
	res.send "PUT /fotos/#{user}/#{slug}", 'Content-Type': 'text/plain'


app.delete '/fotos/:user/:slug', middleware.auth, (req, res) ->
	user = req.param 'user'
	slug = req.param 'slug'
	res.send "DELETE /fotos/#{user}/#{slug}", 'Content-Type': 'text/plain'


app.get '/perfil', middleware.auth, (req, res) ->
	res.send "GET /perfil", 'Content-Type': 'text/plain'


app.put '/perfil', middleware.auth, (req, res) ->
	res.send "PUT /perfil", 'Content-Type': 'text/plain'


app.get '/tweets', middleware.auth, (req, res) ->
	res.send "GET /tweets", 'Content-Type': 'text/plain'


# app.all '*', (req, res) ->
# 	res.render 'gallery'


# Only listen on $ node app.js
if (!module.parent)
	app.listen 3000
	console.log "Listening on port %d", app.address().port