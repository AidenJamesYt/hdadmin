-- LOCAL
local main = require(game.Nanoblox)
local System = main.modules.System
local CommandService = System.new("Commands")
CommandService.remotes = {}



-- START
function CommandService.start()

    local previewCommand = main.modules.Remote.new("previewCommand")
    CommandService.remotes.previewCommand = previewCommand
    
end



-- PLAYER USER LOADED
function CommandService.userLoadedMethod(user)
	CommandService.setupParsePatterns(user)
end



-- BEGIN
function CommandService.loaded()
	
	-- Setup globals
	CommandService.executeStatementGloballySender = main.services.GlobalService.createSender("executeStatementGlobally")
	CommandService.executeStatementGloballyReceiver = main.services.GlobalService.createReceiver("executeStatementGlobally")
	CommandService.executeStatementGloballyReceiver.onGlobalEvent:Connect(function(callerUserId, statement)
		CommandService.executeStatement(callerUserId, statement)
	end)

	-- Grab default commands
	local defaultCommands = main.modules.Commands
	for name, details in pairs(defaultCommands) do
		CommandService.createCommand(name, details)
	end

	-- Setup auto sorters
	local records = CommandService.records
	records:setTable("dictionary", function()
		local dictionary = {}
		for _, record in pairs(records) do
			dictionary[record.name] = record
			for _, alias in pairs(record.aliases) do
				dictionary[alias] = record
			end
		end
		return dictionary
	end, true)
	records:setTable("lowerCaseNameAndAliasToCommandDictionary", function()
		local dictionary = {}
		for _, record in pairs(records) do
			dictionary[record.name:lower()] = record
			for _, alias in pairs(record.aliases) do
				dictionary[alias:lower()] = record
			end
		end
		return dictionary
	end, true)
	records:setTable("sortedNameAndAliasLengthArray", function()
		local array = {}
		for itemNameOrAlias, record in pairs(records:getTable("dictionary")) do
			table.insert(array, itemNameOrAlias)
		end
		table.sort(array, function(a, b) return #a > #b end)
		return array
	end)

end



-- EVENTS
CommandService.recordAdded:Connect(function(commandName, record)
	--warn(("COMMAND '%s' ADDED!"):format(commandName))
end)

CommandService.recordRemoved:Connect(function(commandName)
	--warn(("COMMAND '%s' REMOVED!"):format(commandName))
end)

CommandService.recordChanged:Connect(function(commandName, propertyName, propertyValue, propertyOldValue)
	--warn(("BAN '%s' CHANGED %s to %s"):format(commandName, tostring(propertyName), tostring(propertyValue)))
end)



-- METHODS
function CommandService.generateRecord(key)
	local defaultCommands = main.modules.Commands
	return defaultCommands[key] or {
		name = "", -- This will be locked, command names cannot change and must always be the same
		description = "",
		contributors = {},
		aliases	= {},
		opposites = {}, -- the names to undo (revoke) the command, e.g. ;invisible would have 'visible'
		prefixes = {},
		tags = {},
		args = {},
		blockPeers = false,
		blockJuniors = false,
		autoPreview = false,
		requiresRig = nil,
		remoteNames = {},
		receiverNames = {},
		senderNames = {},
	}
end

function CommandService.createCommand(name, properties)
	local key = properties.name
	if not key then
		key = name
		properties.name = key
	end
	local record = CommandService:createRecord(key, false, properties)
	return record
end

function CommandService.getCommand(name)
	local command = CommandService:getRecord(name)
	if not command then
		command = CommandService.getTable("lowerCaseNameAndAliasToCommandDictionary")[name:lower()]
		if not command then
			return false
		end
	end
	return command
end
 
function CommandService.getCommands()
	return CommandService:getRecords()
end

function CommandService.updateCommand(name, propertiesToUpdate)
	CommandService:updateRecord(name, propertiesToUpdate)
	return true
end

function CommandService.removeCommand(name)
	CommandService:removeRecord(name)
	return true
end

function CommandService.getTable(name)
	return CommandService.records:getTable(name)
end 

function CommandService.setupParsePatterns(user)
	-- This dynamically updates the players 'parsePatterns' when the users settings change instead of having to parse them every chat message
	local PARSE_SETTINGS = {
		commandStatementsFromBatch = {
			settingName = "prefixes",
			parse = function(settingValue)
				return string.format(
					"%s([^%s]+)",
					";", --ClientSettings.prefix,
					";" --ClientSettings.prefix
				)
			end,
		},
        descriptionsFromCommandStatement = {
			settingName = "descriptorSeparator",
			parse = function(settingValue)
				return string.format(
					"%s?([^%s]+)",
					" ", --ClientSettings.descriptorSeparator,
					" " --ClientSettings.descriptorSeparator
				)
			end,
		},
        argumentsFromCollection = {
			settingName = "collective",
			parse = function(settingValue)
				return string.format(
					"([^%s]+)%s?",
					",", --ClientSettings.collective,
					"," --ClientSettings.collective
				)
			end,
		},
        capsuleFromKeyword = {
			settingName = "argCapsule",
			parse = function(settingValue)
				return string.format(
					"%%(%s%%)", --Capsule
					string.format("(%s)", ".-")
				)
			end
		},
	}
	local validSettingNames = {}
	local playerSettings = user.perm:getOrSetup("playerSettings")
	playerSettings.changed:Connect(function(settingName, value)
		if validSettingNames[settingName] then
			user.temp.parsePatterns:set(settingName, value)
		end
	end)
	user.temp:set("parsePatterns", {})
	for _, detail in pairs(PARSE_SETTINGS) do
		local settingName = detail.settingName
		local settingValue = main.services.SettingService.getPlayerSetting(settingName, user)
		validSettingNames[settingName] = true
		user.temp.parsePatterns:set(settingName, settingValue)
	end
end

function CommandService.createFakeUser(userId)
	local DEFAULT_USER_ID = 1
	local user = {}
	user.userId = userId or DEFAULT_USER_ID
	user.name = "Server"
	user.displayName = "Server"
	user.perm = main.modules.State.new({
		playerSettings = {
			playerIdentifier = "@",
			playerUndefinedSearch = main.enum.PlayerSearch.UserName,
			playerDefinedSearch = main.enum.PlayerSearch.DisplayName,
		}
	}, true)
	user.temp = main.modules.State.new(nil, true)
	user.roles = {}
	CommandService.setupParsePatterns(user)
	-- if DEFAULT_USER_ID then get creator role, else use RoleService
	main.services.RoleService.getCreatorRole():give(user, main.enum.RoleType.Server)
	return user
end

function CommandService.chatCommand(callerUser, message)
	local callerUserId = callerUser.userId
	local callerPlayer = callerUser.player
	local batch = main.modules.Parser.parseMessage(message, callerUser)
	print(callerUser.name, "chatted: ", message, batch)
	if type(batch) == "table" then
		for _, statement in pairs(batch) do
			local approved, noticeDetails = CommandService.verifyStatement(callerUser, statement)
			if approved then
				CommandService.executeStatement(callerUserId, statement)
			end
			if callerPlayer then
				for _, detail in pairs(noticeDetails) do
					local method = main.services.MessageService[detail[1]]
					method(callerPlayer, detail[2])
				end
			end
		end
	end
end

function CommandService.verifyStatement(callerUser, statement)
	local approved = true
	local details = {}

	local jobId = statement.jobId
	local statementCommands = statement.commands
	local modifiers = statement.modifiers
	local qualifiers = statement.qualifiers

	-- This verifies the caller can use the given commands and associated arguments
	if statementCommands then
		for commandName, arguments in pairs(statementCommands) do
			
			-- Does the command exist
			local command = main.services.CommandService.getCommand(commandName)
			if not command then
				return false, {{"notice", {
					text = string.format("'%s' is an invalid command name!", commandName),
					error = true,
				}}}
			end

			-- Does the caller have permission to use it
			local commandNameLower = string.lower(commandName)
			if not main.services.RoleService.verifySetting(callerUser, "commands").has(commandNameLower) then
				--!!! RE_ENABLE THIS
				--[[return false, {{"notice", {
					text = string.format("You do not have permission to use command '%s'!", commandName),
					error = true,
				}}}--]]
			end

			-- Does the caller have permission to use the associated arguments of the command
			for i, argString in pairs(arguments) do
				local argName = command.args[i]
				local argItem = main.modules.Parser.Args.get(argName)
				if argItem.verifyCanUse then
					local canUseArg, deniedReason = argItem:verifyCanUse(callerUser, argString)
					if not canUseArg then
						return false, {{"notice", {
							text = deniedReason,
							error = true,
						}}}
					end
				end
			end

		end
	end

	-- This adds an additional notification if global as these commands can take longer to execute
	if modifiers.global then
		table.insert(details, {"notice", {
			text = "Executing global command...",
			error = false,
		}})
	end

	return approved, details
end

function CommandService.executeStatement(callerUserId, statement)
	----
	statement.commands = statement.commands or {}
	statement.modifiers = statement.modifiers or {}
	statement.qualifiers = statement.qualifiers or {}
	----
	local tasks = {}
	local Modifiers = main.modules.Parser.Modifiers
	for modifierName, _ in pairs(statement.modifiers) do
		local modifierItem = Modifiers.get(modifierName)
		if modifierItem then
			local continueExecution = modifierItem.preAction(callerUserId, statement)
			if not continueExecution then
				return tasks
			end
		end
	end
	local Args = main.modules.Parser.Args
	local Promise = main.modules.Promise
	local promises = {}
	local isPermModifier = statement.modifiers.perm
	local isGlobalModifier = statement.modifiers.wasGlobal
	for commandName, arguments in pairs(statement.commands) do
		local command = CommandService.getCommand(commandName)
		print("command = ", commandName, command)
		local executeForEachPlayerFirstArg = Args.executeForEachPlayerArgsDictionary[string.lower(command.args[1])]
		local TaskService = main.services.TaskService
		local properties = TaskService.generateRecord()
		properties.callerUserId = callerUserId
		properties.commandName = commandName
		properties.args = arguments or properties.args
		properties.modifiers = statement.modifiers
		-- Its important to split commands into specific users for most cases so that the command can
		-- be easily reapplied if the player rejoins (for ones where the perm modifier is present)
		-- The one exception for this is when a global modifier is present. In this scenerio, don't save
		-- specific targets, simply use the qualifiers instead to select a general audience relevant for
		-- the particular server at time of exection.
		-- e.g. ``;permLoopKillAll`` will save each specific target within that server and permanetly loop kill them
		-- while ``;globalLoopKillAll`` will permanently save the loop kill action and execute this within all
		-- servers repeatidly
		local addToPerm = false
		local splitIntoUsers = false
		if isPermModifier then
			if isGlobalModifier then
				addToPerm = true
			elseif executeForEachPlayerFirstArg then
				addToPerm = true
				splitIntoUsers = true
			end
		else
			splitIntoUsers = executeForEachPlayerFirstArg
		end
		if not splitIntoUsers then
			properties.qualifiers = statement.qualifiers or properties.qualifiers
			table.insert(tasks, main.services.TaskService.createTask(addToPerm, properties))
		else
			table.insert(promises, Promise.defer(function(resolve)
				local targets = Args.get("player"):parse(statement.qualifiers, callerUserId)
				for _, plr in pairs(targets) do
					properties.targetUserId = plr.UserId
					local task = main.services.TaskService.createTask(addToPerm, properties)
					if task then
						table.insert(tasks, task)
					end
				end
				resolve()
			end):catch(warn))
		end
	end
	return Promise.all(promises)
		:andThen(function()
			return tasks
		end)
end

function CommandService.executeSimpleStatement(callerUserId, commandName, optionalCommandArgs, optionalQualifiers, optionalModifiers)
	CommandService.executeStatement(callerUserId, {
		commands = {
			[commandName] = optionalCommandArgs or {}
		},
		qualifiers = optionalQualifiers or {},
		modifiers = optionalModifiers or {},
	})
end

--[[

local statement = {
	jobId = game.JobId;
	commands = {
		noobify = {"red"},
		goldify = {"red"},
	},
	modifiers = {
		global = {},
		random = {},
	},
	qualifiers = {
		random = {"ben", "matt", "sam"},
		me = true,
		nonadmins = true,
	},
}

]]



return CommandService