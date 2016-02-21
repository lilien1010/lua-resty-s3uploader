
cal http = require "resty.http"
local json = require "cjson"
 
local resty_string       = require "resty.string" 

local base64_decode =   ngx.decode_base64 
local base64_encode =   ngx.encode_base64

local ngx_http_time =   ngx.http_time 
local ngx_md5       =   ngx.md5
local ngx_md5_bin   =   ngx.md5_bin
local ngx_time      =   ngx.time 
local ngx_today     =   ngx.today
local string_len    =   string.len
local string_sub    =   string.sub
local sha1          =   ngx.hmac_sha1

local _M    =   { 

    __accessKey =   '1233423123';		-- default accessKey
    __secretKey =   "2312333333333333333333";	--default secretKey
    
    ACL_PRIVATE             = 'private';
    ACL_PUBLIC_READ         = 'public-read';    
    ACL_PUBLIC_READ_WRITE   = 'public-read-write';  
    
}   

-- content type and 
local allowd_types= {
    ['voice/htk']                   =   'hta';
    ['voice/hta']                   =   'hta';
    ['image/jpeg']                  =   'jpg';
    ['image/png']                   =   'png';  
    ['image/gif']                   =   'gif'; 
    ['image/jpg']                   =   'jpg'; 
    ['image/bmp']                   =   'bmp'; 
    ['image/x-icon']                =   'ico'; 
    ['image/tiff']                  =   'tiff'; 
    ['image/vnd.wap.wbmp']          =   'webp';  
    ['image/vod']                   =   'vod'; 
    ['video/mp4']                   =   'mp4'; 
    ['application/htk']             =   'hta'; 
    ['application/hta']             =   'hta'; 
    ['application/octet-stream']    =   'hta'; 
}

_M.allowd_types     =   allowd_types

local mt    = { __index = _M }

function _M:new(accessKey,secretKey,_bucket,timeout)
    
    return setmetatable({
        __accessKey =   accessKey;
        __secretKey =   secretKey;
        _bucket     =   _bucket;
        timeout     =   timeout or 10000;
        content_md5_bin     =   '';
        is_image    =   false;
        object_name =   false;
    },mt)
    
end


function _M:__getSignature(str)
    -- public static function __getSignature(str) {
     -- return 'AWS '.self::$__accessKey.':'.base64_encode(hash_hmac('sha1', $string, self::$__secretKey, true)  );
    -- }   
    local digest = sha256:final() 
    
    local service = 'AWS'
    local key   =   base64_encode(sha1(self.__secretKey,str))
    return service..' '.. self.__accessKey ..':'..key
end

 
 

function _M:_getV4Signature(region,service)
 
    local kSecret   =   self.__secretKey
    
    local Date      =   self.getDate()
    
    local kDate     = HMAC("AWS4" .. kSecret, Date)
 
    local kRegion   = HMAC(kDate, Region) 
    local kService  = HMAC(kRegion, Service) 
    local kSigning  = HMAC(kService, "aws4_request")
    
    return resty_string.to_hex(kSigning)
end

function _M:build_auth_headers(content,acl,content_type,bucket,uri)

    local Date      =   ngx_http_time(ngx_time());
    local re        =   acl or self.ACL_PUBLIC_READ
    
    local verb      =   'PUT'
    local MD5       =   base64_encode(self.content_md5_bin)
    content_type        =   content_type or  "application/octet-stream"
    local amz       =   "\nx-amz-acl:"..acl
    local resource  =   '/'..bucket..'/'..uri;
    
    local CL        =   string.char(10);
    
    local check_param   =   verb..CL..MD5..CL..content_type..CL..Date..amz..CL..resource
 
    -- ngx.log(ngx.INFO,'len =',string_len(check_param),' ,check_param=',check_param)
    
    return {
        ['x-amz-acl']       =   acl;   
        ['Date']            =   Date;  
        ['Content-MD5']     =   MD5;  
        ['Content-Type']    =   content_type;  
        ['Authorization']   =    _M:__getSignature(check_param);  
    }
    
end

function _M:getDate()
    if self['ht_date'] then
        return self['ht_date'] 
    end
    
    local today =   ngx_today();
    local reg   =   [[(\d{4})-(\d{2})-(\d{2})]] 
    local newstr, n, err = ngx.re.gsub(today, reg, "$1$2$3", "i")
    if newstr then
        self['ht_date'] =   newstr
    else
        self['ht_date'] =   '20160126'
    end
    return self['ht_date'];
end

function _M:get_obejct_name(content,content_type)
 
    local local_date    =   self:getDate()
     
    -- add time as md5 element so that the  same file generate different filename
    -- if you want save your S3 space you can change the code below into `ngx_md5(self.content_md5_bin)`
    local md5       =   ngx_md5(self.content_md5_bin .. ngx_time())
    local md5sum    =   string_sub(md5,4,20)..'_'..string_sub(md5,28,32);
    local filename  =   local_date..'/'..md5sum..'.'..(allowd_types[content_type] or 'obj')
    return filename;
end

-- judge is image or not
function _M:is_content_image(content_type)
    local name  =   allowd_types[content_type]
    
    if  'jpeg' == name or 
        'png' == name or 
        'gif' == name or  
        'jpg' == name or 
        'bmp' == name   
    then
        return name
    else
        return nil
    end
    
end

function _M:upload(content, content_type, object_name )
    
    self.content_md5_bin    =   ngx_md5_bin(content)
    
    object_name     =   object_name or self:get_obejct_name(content,content_type)
    local s3_host           =   's3.amazonaws.com';
    local bucket_host       =   self._bucket .."."..s3_host 
    local host              =   "http://"..bucket_host
    local final_url         =   host..'/'..object_name
      
     local headers, err = self:build_auth_headers(content,self.ACL_PUBLIC_READ,content_type,self._bucket,object_name)
 
    
     if not headers then return nil, err end
 
     local httpc = http.new()
    
    headers['Host'] =   bucket_host
     
    -- ngx.log(ngx.ERR,'headers=',json.encode(headers))
    
    httpc:set_timeout(self.timeout)
    local res, err = httpc:request_uri(final_url, {
        method = "PUT",
        body = content,
        headers = headers
      })
     
    if not res then 
        err =   err     or  '' 
        return nil,self._bucket.. ' '..err
    end 
    
     -- for k,v in pairs(res.headers) do
        -- ngx.log(ngx.ERR,"Header ", k,' = ',v)
     -- end 
     
    -- local    body, err = res:read_body()
    
    if  307 == res.status then
        ngx.log(ngx.ERR,' post redirect happen')
        if res.headers['Location'] then 
        
            local new_url   =   res.headers['Location']
             
            ngx.log(ngx.ERR,'307 new_url',new_url)
            
            local httpc = http.new()
            local res, err = httpc:request_uri(new_url, {
                method = "PUT",
                body = content,
                headers = headers
              })
                   
            if not res then 
                err =   err     or  '' 
                return nil,self._bucket.. ' '..err
            end 
            if  200 ~= res.status then
                ngx.log(ngx.ERR,'307 s3_upload aws err',res.body)
                return nil,res.status..' code ,body='..res.body
            end
            return new_url,res.body
        else
            ngx.log(ngx.ERR,'307 but no Location')
        end
     
    elseif  200 ~= res.status then
        ngx.log(ngx.ERR,'s3_upload aws err',res.body)
        return nil,res.status..' code ,body='..res.body
    end
    
    
       
    return  final_url,object_name
        
end


return _M
