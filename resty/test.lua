local cnf 		= 	require "config.HTconfig"
local upload 	= 	require "resty.upload"
-- clone from https://github.com/openresty/lua-resty-upload
local json 		=	require "cjson"
local s3_upload	=	require "resty.s3_upload"

local base64_decode	=	ngx.decode_base64 
local base64_encode	=	ngx.encode_base64
local string_len	=	string.len
local ngx_find		=	ngx.re.find
local chunk_size 	=	1024*10 -- should be set to 4096 or 8192
				 
local ngx_gsub		=	ngx.re.gsub
local string_sub		=	string.sub

local form, err = upload:new(chunk_size)
if not form then
	ngx.log(ngx.ERR, "failed to new upload: ", err)
	ngx.exit(500)
end

local allowd_types	=	s3_upload.allowd_types
local timeOut		=	cnf.S3_UPLOAD_TIMEOUT
form:set_timeout(timeOut) -- 1 sec
 
local appender			=	''
local start_upload		=	false;
local data_upload		=	false;
local content_type		=	'';
local data_ready		=	false;
  
local uploader = s3_upload:new(cnf.AWS_accessKey,cnf.AWS_secretKey,cnf.CHATVOC_BUCKET,timeOut)
 
 
while true do
		local typ, res, err = form:read()
		if not typ then
			ngx.say(ngx.ERR,"failed to read: ", err)
			return
		end 
		
		if typ == "header" then 
			content_type	=	res[2]
			ngx.log(ngx.INFO,"content_type: ", content_type)
            if content_type and allowd_types[content_type] then 
            		start_upload	=	true
            end 
			
			local inputFile	=	[[name="input"]]
			if res[1]=='Content-Disposition' and  ngx_find(res[2] or '',inputFile) then 
            		data_upload	=	true
            end
			ngx.log(ngx.INFO,"header: ", json.encode(res))
			
		elseif typ == "body" then
			if start_upload==true and res then
				appender	=	appender..res
			end
			
			if data_upload == true and res then
				ngx.log(ngx.NOTICE,"body : ", res)
				data_upload	=	false
			end
				

		elseif typ == "part_end" then 
		 	
		 	if appender ~= ''  then
				local data_len 	=	 string_len(appender)
				ngx.log(ngx.NOTICE,"start to upload ",content_type," len=" ,data_len)
				
				if data_len>20 then 
				
					local filename	=	ngx.md5(appender)
					
					local url,object_err	=	uploader:upload(appender,content_type)
					 
					if not url then
						 
						 ngx.log(ngx.ERR, "postfix or url err ",postfix , url)
					end
					
					if url then
						local show 	=	json.encode({status="0";url=url})
						ngx.print (show)
						ngx.log(ngx.NOTICE,"success : ",show)
					else
						ngx.print (json.encode({status="507";url=url;err=err}))
						ngx.log(ngx.ERR,"request return : ",err)
					end 
				else
					local reason 	=	" body too short  " .. content_type
					ngx.log(ngx.NOTICE,reason)
					ngx.print (json.encode({status="507" ;err=reason}))
		 		end
				appender		= 	''
				start_upload	= 	false
		 	end 
		 
    elseif typ == "eof" then
         break 
    end 
end 