# oauthd
# http://oauth.io
#
# Copyright (c) 2013 thyb, bump
# For private use only.

crypto = require 'crypto'
restify = require 'restify'
restifyOAuth2 = require 'restify-oauth2-oauthd'
shared = require '../shared'

_config =
	expire: 3600*5

hooks =
	grantClientToken: (clientId, clientSecret, cb) ->
		shared.db.users.login clientId, clientSecret, (err, res) ->
			return cb null, false if err
			token = shared.db.generateUid clientId + ':' + clientSecret
			(shared.db.redis.multi [
				['hmset', 'session:' + token, 'id', res.id, 'mail', res.mail]
				['expire', 'session:' + token, _config.expire]
			]).exec (err, r) ->
				return cb err if err
				shared.emit 'user.login'
				return cb null, token

	authenticateToken: (token, cb) ->
		shared.db.redis.hgetall 'session:' + token, (err, res) ->
			return cb err if err
			return cb null, false if not res
			return cb null, res

exports.init = ->
	restifyOAuth2.cc @server,
		hooks:hooks, tokenEndpoint:@config.base+'/token',
		tokenExpirationTime: _config.expire

exports.needed = (req, res, next) ->
	if not req.clientId
		return next new restify.UnauthorizedError "You need authentication"
	req.user = req.clientId
	req.body ?= {}
	if not req.params.key?
		return next()
	shared.db.users.hasApp req.user.id, req.params.key, (err, res) ->
		return next err if err
		if not req.user.mail.match /.*@oauth\.io$/
			return next new restify.NotAuthorizedError "You have not access to this app" if not res
		next()

exports.adm = (req, res, next) ->
	exports.needed req, res, (e) ->
		return next e if e
		if not req.user.mail.match /.*@oauth\.io$/
			return next new restify.NotAuthorizedError
		next()

exports.optional = (req, res, next) ->
	req.user = req.clientId
	req.body ?= {}
	next()

exports.setup = (callback) ->
	@server.post '/signin', (req, res, next) =>
		res.setHeader 'Content-Type', 'text/html'
		hooks.grantClientToken req.body.mail, req.body.pass, (e, token) =>
			return next(e) if e
			# return next(new @check.Error 'Bad credentials') if not token
			if token
				res.setHeader 'Set-Cookie', 'accessToken=%22' + token + '%22; Path=/; Expires=' + new Date((new Date-0)+_config.expire*1000)
			res.setHeader 'Location', @config.host_url + '/key-manager'
			res.send 302
			next()
	callback()

shared.auth = exports