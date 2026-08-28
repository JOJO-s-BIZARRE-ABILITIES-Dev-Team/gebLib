-- Original implementation by yobson1
-- Improved version by el_tomlino

local soundCache = {}
local mp3FrameHeaderCache = {}

local MP3Data = {
	versions = {"2.5", false, "2", "1"},
	layers = {false, 3, 2, 1},
	bitrates = {
		["1"] = {
			[1] = {0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448},
			[2] = {0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384},
			[3] = {0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320}
		},
		["2"] = {
			[1] = {0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 288},
			[2] = {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160},
			[3] = {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160}
		}
	},
	sampleRates = {
		["1"] = {44100, 48000, 32000},
		["2"] = {22050, 24000, 16000},
		["2.5"] = {11025, 12000, 8000}
	},
	samples = {
		["1"] = {
			[1] = 384,
			[2] = 1152,
			[3] = 1152
		},
		["2"] = {
			[1] = 384,
			[2] = 1152,
			[3] = 576
		}
	}
}

local function ReadUInt16LE(buffer)
	local b0, b1 = buffer:ReadByte(), buffer:ReadByte()
	if b0 == nil or b1 == nil then return nil end
	return b0 + b1 * 256
end

local function ReadUInt32LE(buffer)
	local b0, b1, b2, b3 = buffer:ReadByte(), buffer:ReadByte(), buffer:ReadByte(), buffer:ReadByte()
	if b0 == nil or b1 == nil or b2 == nil or b3 == nil then return nil end
	return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function ReadUInt32BE(buffer)
	local b0, b1, b2, b3 = buffer:ReadByte(), buffer:ReadByte(), buffer:ReadByte(), buffer:ReadByte()
	if b0 == nil or b1 == nil or b2 == nil or b3 == nil then return nil end
	return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3
end

local function ValidDuration(duration)
	return isnumber(duration) and duration > 0 and duration < math.huge
end

local function MP3FrameSize(samples, layer, bitrate, sampleRate, paddingBit)
	local size

	if layer == 1 then
		size = math.floor(((samples * bitrate * 125) / sampleRate) + paddingBit * 4)
	else
		size = math.floor(((samples * bitrate * 125) / sampleRate) + paddingBit)
	end

	return (size == size and size < math.huge) and size or 0
end

local function ParseMP3FrameHeader(buffer)
	local header = buffer:Read(4)
	if not header or #header ~= 4 then return nil end
	local syncByte, versionLayerByte, bitrateSampleByte, channelByte = string.byte(header, 1, 4)

	if syncByte ~= 0xff
		or bit.band(versionLayerByte, 0xe0) ~= 0xe0
	then
		return nil
	end

	local channelMode = bit.rshift(bit.band(channelByte, 0xc0), 6)
	local cacheKey = versionLayerByte * 1024 + bitrateSampleByte * 4 + channelMode
	local cachedHeader = mp3FrameHeaderCache[cacheKey]
	if cachedHeader then return cachedHeader end

	-- Get the version
	local versionBits = bit.rshift(bit.band(versionLayerByte, 0x18), 3)
	local version = MP3Data.versions[versionBits + 1]
	if not version then return nil end
	local simpleVersion = version == "2.5" and "2" or version

	-- Get the layer
	local layerBits = bit.rshift(bit.band(versionLayerByte, 0x06), 1)
	local layer = MP3Data.layers[layerBits + 1]
	if not layer then return nil end

	-- Get the bitrate
	local bitrateIndex = bit.rshift(bit.band(bitrateSampleByte, 0xf0), 4)
	if bitrateIndex == 0 or bitrateIndex == 15 then return nil end
	local bitrate = MP3Data.bitrates[simpleVersion][layer][bitrateIndex + 1] or 0

	-- Get the sample rate
	local sampleRateIdx = bit.rshift(bit.band(bitrateSampleByte, 0x0c), 2)
	if sampleRateIdx == 3 then return nil end
	local sampleRate = MP3Data.sampleRates[version][sampleRateIdx + 1] or 0

	local sample = MP3Data.samples[simpleVersion][layer]

	-- Get padding bit
	local paddingBit = bit.rshift(bit.band(bitrateSampleByte, 0x02), 1)
	local frameSize = MP3FrameSize(sample, layer, bitrate, sampleRate, paddingBit)
	if frameSize <= 4 then return nil end

	local frameHeader = {
		version = version,
		layer = layer,
		bitrate = bitrate,
		sampleRate = sampleRate,
		frameSize = frameSize,
		samples = sample,
		hasCRC = bit.band(versionLayerByte, 0x01) == 0,
		mono = channelMode == 3
	}
	mp3FrameHeaderCache[cacheKey] = frameHeader
	return frameHeader
end

local function MP3FrameDuration(frameHeader, frameCount)
	local duration = frameCount * frameHeader.samples / frameHeader.sampleRate
	return ValidDuration(duration) and duration or nil
end

local function ParseMP3VBRDuration(buffer, framePosition, frameHeader)
	if frameHeader.layer ~= 3 then return nil end

	local bufferSize = buffer:Size()
	local crcSize = frameHeader.hasCRC and 2 or 0
	local sideInfoSize
	if frameHeader.version == "1" then
		sideInfoSize = frameHeader.mono and 17 or 32
	else
		sideInfoSize = frameHeader.mono and 9 or 17
	end

	local xingPosition = framePosition + 4 + crcSize + sideInfoSize
	if xingPosition + 12 <= bufferSize then
		buffer:Seek(xingPosition)
		local marker = buffer:Read(4)
		if marker == "Xing" or marker == "Info" then
			local flags = ReadUInt32BE(buffer)
			if flags and bit.band(flags, 0x01) ~= 0 then
				local frameCount = ReadUInt32BE(buffer)
				local duration = frameCount and MP3FrameDuration(frameHeader, frameCount)
				if duration then return duration end
			end
		end
	end

	-- Fraunhofer VBRI begins 32 bytes after the four-byte MPEG header.
	local vbriPosition = framePosition + 36
	if vbriPosition + 18 <= bufferSize then
		buffer:Seek(vbriPosition)
		if buffer:Read(4) == "VBRI" then
			buffer:Skip(10)
			local frameCount = ReadUInt32BE(buffer)
			local duration = frameCount and MP3FrameDuration(frameHeader, frameCount)
			if duration then return duration end
		end
	end

	return nil
end

local function SkipID3v2(buffer)
	buffer:Seek(0)
	if buffer:Read(3) ~= "ID3" then
		buffer:Seek(0)
		return true
	end

	local majorVersion = buffer:ReadByte()
	buffer:Skip(1)
	local flags = buffer:ReadByte()
	local z0, z1, z2, z3 = buffer:ReadByte(), buffer:ReadByte(), buffer:ReadByte(), buffer:ReadByte()
	if majorVersion == nil or flags == nil or z0 == nil or z1 == nil or z2 == nil or z3 == nil then
		return false
	end
	if majorVersion < 2 or majorVersion > 4
		or bit.band(z0, 0x80) ~= 0
		or bit.band(z1, 0x80) ~= 0
		or bit.band(z2, 0x80) ~= 0
		or bit.band(z3, 0x80) ~= 0
	then
		return false
	end

	local footerSize = majorVersion == 4 and bit.band(flags, 0x10) ~= 0 and 10 or 0
	local payloadSize = z0 * 2097152 + z1 * 16384 + z2 * 128 + z3
	local tagEnd = 10 + payloadSize + footerSize
	if tagEnd > buffer:Size() then return false end

	buffer:Seek(tagEnd)
	return true
end

local function HasFollowingMP3Frame(buffer, framePosition, frameHeader)
	local nextFramePosition = framePosition + frameHeader.frameSize
	local bufferSize = buffer:Size()
	if nextFramePosition == bufferSize then return true end
	if nextFramePosition + 4 > bufferSize then return false end

	buffer:Seek(nextFramePosition)
	local nextFrame = ParseMP3FrameHeader(buffer)
	return nextFrame ~= nil and nextFramePosition + nextFrame.frameSize <= bufferSize
end

local function DecodeMP3(buffer, checkpoint)
	if not SkipID3v2(buffer) then return nil end

	local duration = 0
	local foundFrame = false
	local bufferSize = buffer:Size()
	local framePosition = buffer:Tell()
	while framePosition + 4 <= bufferSize do
		if checkpoint then checkpoint() end
		buffer:Seek(framePosition)
		local frameHeader = ParseMP3FrameHeader(buffer)
		if frameHeader and framePosition + frameHeader.frameSize <= bufferSize then
			if not foundFrame then
				local vbrDuration = ParseMP3VBRDuration(buffer, framePosition, frameHeader)
				if vbrDuration then return vbrDuration end

				if not HasFollowingMP3Frame(buffer, framePosition, frameHeader) then
					framePosition = framePosition + 1
				else
					foundFrame = true
				end
			end

			if foundFrame then
				duration = duration + frameHeader.samples / frameHeader.sampleRate
				framePosition = framePosition + frameHeader.frameSize
			end
		else
			if foundFrame then break end
			framePosition = framePosition + 1
		end
	end

	return ValidDuration(duration) and duration or nil
end

local function DecodeWAV(buffer, checkpoint)
	local bufferSize = buffer:Size()
	if bufferSize < 12 then return nil end

	buffer:Seek(0)
	if buffer:Read(4) ~= "RIFF" then return nil end
	local riffSize = ReadUInt32LE(buffer)
	if riffSize == nil or buffer:Read(4) ~= "WAVE" then return nil end

	local riffEnd = riffSize + 8
	if riffEnd > bufferSize then return nil end

	local byteRate
	local dataSize
	while buffer:Tell() + 8 <= riffEnd do
		if checkpoint then checkpoint() end
		local chunkID = buffer:Read(4)
		local chunkSize = ReadUInt32LE(buffer)
		if not chunkID or chunkSize == nil then return nil end

		local chunkData = buffer:Tell()
		local chunkEnd = chunkData + chunkSize
		if chunkEnd > riffEnd then return nil end

		if chunkID == "fmt " and chunkSize >= 16 then
			local format = ReadUInt16LE(buffer)
			local channels = ReadUInt16LE(buffer)
			local sampleRate = ReadUInt32LE(buffer)
			local parsedByteRate = ReadUInt32LE(buffer)
			local blockAlign = ReadUInt16LE(buffer)
			local bitsPerSample = ReadUInt16LE(buffer)
			if format and format > 0
				and channels and channels > 0
				and sampleRate and sampleRate > 0
				and parsedByteRate and parsedByteRate > 0
				and blockAlign and blockAlign > 0
				and bitsPerSample and bitsPerSample > 0
			then
				byteRate = parsedByteRate
			end
		elseif chunkID == "data" and chunkSize > 0 then
			dataSize = chunkSize
		end

		if byteRate and dataSize then
			local duration = dataSize / byteRate
			return ValidDuration(duration) and duration or nil
		end

		local nextChunk = chunkEnd + chunkSize % 2
		if nextChunk > riffEnd then return nil end
		buffer:Seek(nextChunk)
	end

	return nil
end

local soundDecoders = {
	mp3 = DecodeMP3,
	wav = DecodeWAV
}

local ASYNC_HOOK = "gebLib.SoundDurationAsync"
local ASYNC_PARSE_BUDGET = 0.0005
local ASYNC_CLIENT_LIMIT = 2

local asyncRequests = {}
local clientQueue = {}
local clientQueueHead = 1
local clientQueueTail = 0
local clientActive = 0
local clientPumping = false
local decodeQueue = {}
local decodeQueueHead = 1
local decodeQueueTail = 0
local decodeWorker
local asyncReadActive = false
local asyncHookActive = false
local asyncDeadline = 0
local asyncCheckpointCount = 0

local StringBuffer = {}
StringBuffer.__index = StringBuffer

function StringBuffer:Read(length)
	if self.position >= self.size then return nil end
	local value = string.sub(self.data, self.position + 1, self.position + length)
	self.position = self.position + #value
	return value
end

function StringBuffer:ReadByte()
	local value = string.byte(self.data, self.position + 1)
	if value ~= nil then self.position = self.position + 1 end
	return value
end

function StringBuffer:Tell()
	return self.position
end

function StringBuffer:Seek(position)
	self.position = position
	return position
end

function StringBuffer:Skip(offset)
	self.position = self.position + offset
	return self.position
end

function StringBuffer:Size()
	return self.size
end

function StringBuffer:Close() end

local function NewStringBuffer(data)
	return setmetatable({
		data = data,
		position = 0,
		size = #data
	}, StringBuffer)
end

local function NativeSoundDuration(soundPath)
	local duration = SoundDuration(soundPath)
	if ValidDuration(duration) then soundCache[soundPath] = duration end
	return duration
end

local function ReportCallbackError(message)
	if ErrorNoHaltWithStack then
		ErrorNoHaltWithStack("[gebLib] SoundDurationAsync callback failed: " .. tostring(message) .. "\n")
	end
end

local function CompleteAsyncRequest(soundPath, duration)
	if ValidDuration(duration) then soundCache[soundPath] = duration end

	local callbacks = asyncRequests[soundPath]
	asyncRequests[soundPath] = nil
	if not callbacks then return end

	for index = 1, #callbacks do
		local ok, message = pcall(callbacks[index], duration)
		if not ok then ReportCallbackError(message) end
	end
end

local function CompleteWithNativeDuration(soundPath)
	CompleteAsyncRequest(soundPath, NativeSoundDuration(soundPath))
end

local function AsyncDecodeCheckpoint()
	asyncCheckpointCount = asyncCheckpointCount + 1
	if asyncCheckpointCount % 32 == 0 and SysTime() >= asyncDeadline then
		coroutine.yield()
	end
end

local function CloseDecodeWorker()
	if decodeWorker and decodeWorker.buffer then decodeWorker.buffer:Close() end
	decodeWorker = nil
end

local function StartDecodeWorker(soundPath, buffer, decoder)
	asyncCheckpointCount = 0
	decodeWorker = {
		path = soundPath,
		buffer = buffer,
		thread = coroutine.create(function()
			return decoder(buffer, AsyncDecodeCheckpoint)
		end)
	}
end

local ProcessDecodeQueue

local function EnsureAsyncHook()
	if asyncHookActive then return end
	asyncHookActive = true
	hook.Add("Think", ASYNC_HOOK, function()
		ProcessDecodeQueue()
	end)
end

local function StopAsyncHookIfIdle()
	if not asyncHookActive or decodeWorker or asyncReadActive or decodeQueue[decodeQueueHead] then return end
	asyncHookActive = false
	hook.Remove("Think", ASYNC_HOOK)
end

local function QueueDecode(soundPath)
	decodeQueueTail = decodeQueueTail + 1
	decodeQueue[decodeQueueTail] = soundPath
	EnsureAsyncHook()
end

local function PopDecodeQueue()
	local soundPath = decodeQueue[decodeQueueHead]
	if not soundPath then
		decodeQueue = {}
		decodeQueueHead = 1
		decodeQueueTail = 0
		return nil
	end

	decodeQueue[decodeQueueHead] = nil
	decodeQueueHead = decodeQueueHead + 1
	if decodeQueueHead > decodeQueueTail then
		decodeQueue = {}
		decodeQueueHead = 1
		decodeQueueTail = 0
	end
	return soundPath
end

local function StartAsyncRead(soundPath, decoder)
	local function onRead(_, _, status, data)
		asyncReadActive = false
		local successful = status == FSASYNC_OK or FSASYNC_OK == nil and status == 0
		if successful and type(data) == "string" then
			StartDecodeWorker(soundPath, NewStringBuffer(data), decoder)
		else
			CompleteWithNativeDuration(soundPath)
		end
		EnsureAsyncHook()
	end

	if file.AsyncRead then
		asyncReadActive = true
		local ok = pcall(file.AsyncRead, soundPath, "GAME", onRead)
		if ok then return end
		asyncReadActive = false
	end

	local buffer = file.Open(soundPath, "rb", "GAME")
	if buffer then
		StartDecodeWorker(soundPath, buffer, decoder)
	else
		CompleteWithNativeDuration(soundPath)
	end
end

ProcessDecodeQueue = function()
	asyncDeadline = SysTime() + ASYNC_PARSE_BUDGET

	repeat
		if decodeWorker then
			local worker = decodeWorker
			local ok, result = coroutine.resume(worker.thread)
			if not ok then
				CloseDecodeWorker()
				CompleteWithNativeDuration(worker.path)
			elseif coroutine.status(worker.thread) == "dead" then
				CloseDecodeWorker()
				if ValidDuration(result) then
					CompleteAsyncRequest(worker.path, result)
				else
					CompleteWithNativeDuration(worker.path)
				end
			else
				break
			end
		elseif asyncReadActive then
			break
		else
			local soundPath = PopDecodeQueue()
			if not soundPath then break end

			local extension = string.GetExtensionFromFilename(soundPath)
			extension = extension and string.lower(extension)
			local decoder = extension and soundDecoders[extension]
			if decoder then
				StartAsyncRead(soundPath, decoder)
			else
				CompleteWithNativeDuration(soundPath)
			end
		end
	until SysTime() >= asyncDeadline

	StopAsyncHookIfIdle()
end

local PumpClientQueue

local function PopClientQueue()
	local soundPath = clientQueue[clientQueueHead]
	if not soundPath then
		clientQueue = {}
		clientQueueHead = 1
		clientQueueTail = 0
		return nil
	end

	clientQueue[clientQueueHead] = nil
	clientQueueHead = clientQueueHead + 1
	if clientQueueHead > clientQueueTail then
		clientQueue = {}
		clientQueueHead = 1
		clientQueueTail = 0
	end
	return soundPath
end

local function ValidAudioChannel(channel)
	return channel and (not IsValid or IsValid(channel))
end

local function ResolveWithAudioChannel(soundPath)
	clientActive = clientActive + 1
	local ok = pcall(sound.PlayFile, soundPath, "noplay noblock", function(channel)
		clientActive = clientActive - 1
		local duration
		if ValidAudioChannel(channel) and channel.GetLength then
			local lengthOK, length = pcall(channel.GetLength, channel)
			if lengthOK and ValidDuration(length) then duration = length end
		end
		if ValidAudioChannel(channel) and channel.Stop then pcall(channel.Stop, channel) end

		if duration then
			CompleteAsyncRequest(soundPath, duration)
		else
			QueueDecode(soundPath)
		end
		if not clientPumping then PumpClientQueue() end
	end)

	if not ok then
		clientActive = clientActive - 1
		QueueDecode(soundPath)
	end
end

PumpClientQueue = function()
	if clientPumping then return end
	clientPumping = true
	while clientActive < ASYNC_CLIENT_LIMIT do
		local soundPath = PopClientQueue()
		if not soundPath then break end
		ResolveWithAudioChannel(soundPath)
	end
	clientPumping = false
end

local function QueueClientDecode(soundPath)
	clientQueueTail = clientQueueTail + 1
	clientQueue[clientQueueTail] = soundPath
	PumpClientQueue()
end

--- Returns the duration of an MP3 or WAV file and caches valid results by path.
--- Falls back to Garry's Mod's native `SoundDuration` when the file cannot be decoded.
---@param soundPath string Path relative to the `GAME` filesystem, such as `sound/music/example.mp3`.
---@return number duration Duration in seconds, or the native fallback result when decoding fails.
function gebLib.SoundDuration(soundPath)
	if soundCache[soundPath] ~= nil then
		return soundCache[soundPath]
	end

	local extension = string.GetExtensionFromFilename(soundPath)
	extension = extension and string.lower(extension)

	if extension and soundDecoders[extension] then
		local buffer = file.Open(soundPath, "rb", "GAME")
		if not buffer then return NativeSoundDuration(soundPath) end

		local ok, result = pcall(soundDecoders[extension], buffer)
		buffer:Close()
		if ok and ValidDuration(result) then
			soundCache[soundPath] = result
			return result
		end
	end

	return NativeSoundDuration(soundPath)
end

--- Resolves an exact sound duration without scanning an uncached file in one game tick.
--- Cached values invoke the callback immediately. Client requests use an asynchronous
--- audio channel; server and fallback parsing is limited to 0.5 milliseconds per tick.
---@param soundPath string Path relative to the `GAME` filesystem, such as `sound/music/example.mp3`.
---@param callback fun(duration: number) Receives seconds, or the native fallback result when decoding fails.
---@return boolean accepted Whether the request was accepted.
function gebLib.SoundDurationAsync(soundPath, callback)
	if type(soundPath) ~= "string" or soundPath == "" or type(callback) ~= "function" then
		return false
	end

	local cachedDuration = soundCache[soundPath]
	if cachedDuration ~= nil then
		callback(cachedDuration)
		return true
	end

	local callbacks = asyncRequests[soundPath]
	if callbacks then
		callbacks[#callbacks + 1] = callback
		return true
	end

	asyncRequests[soundPath] = {callback}
	if CLIENT and sound and sound.PlayFile then
		QueueClientDecode(soundPath)
	else
		QueueDecode(soundPath)
	end
	return true
end
