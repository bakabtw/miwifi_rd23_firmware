$.ajax({url:window.location.origin+"/cgi-bin/luci/api/xqsystem/init_info",type:"GET",dataType:"json",success:function(rsp){if(rsp.code===0){if(rsp.displayNameLstStr){$(".name").text(rsp.displayNameLstStr)}else{if(rsp.displayName){$(".name").text(rsp.displayName.split(" ").pop());$(".hardware").text(rsp.hardware);$(".romversion").text(rsp.romversion)}}}else{$.alert(rsp.msg)}$("body").show()}});