webpackJsonp([27],{"0f40":function(s,t){},P1wg:function(s,t){},PkfQ:function(s,t,e){"use strict";var a={name:"subtitle",props:{name:{type:String,default:""}}},i={render:function(){var s=this.$createElement,t=this._self._c||s;return t("div",{staticClass:"sub_title"},[t("span"),this._v(" "),t("h4",{attrs:{dir:"rtl"}},[this._v(this._s(this.name))])])},staticRenderFns:[]};var r=e("VU/8")(a,i,!1,function(s){e("0f40")},"data-v-1234106f",null);t.a=r.exports},"u/6M":function(s,t,e){"use strict";Object.defineProperty(t,"__esModule",{value:!0});var a=e("PkfQ"),i={name:"wifi_complete",data:function(){return{}},props:{types:{type:Number,default:1},resultData:{type:Object,default:{}},adminPassword:{type:String,default:""},wireless:{type:Boolean,default:!1}},components:{Subtitle:a.a},created:function(){window.localStorage.removeItem("userProtocal"),2!=this.types&&(this.adminPassword=this.GLOBAL.adminPassword,this.$route.query&&(this.resultData=this.$route.query))},mounted:function(){console.log("destroyed"),localStorage.clear()}},r={render:function(){var s=this,t=s.$createElement,e=s._self._c||t;return e("div",{staticClass:"container complete"},[e("div",{staticClass:"header",class:{headerhas5g:!s.resultData.ssid5g_ssid},attrs:{id:"header"}},[e("div",{staticClass:"iconfont icon-duigou",attrs:{id:"title"}}),s._v(" "),0==s.resultData.bsd&&1==s.resultData.bw160?e("div",[e("p",[s._v(s._s(s.$t("complete.success")))]),s._v(" "),e("p",[s._v(s._s(s.$t("complete.bw160")))])]):e("div",[e("p",[s._v(s._s(s.$t("complete.success")))]),s._v(" "),e("p",[s._v(s._s(s.$t("complete.waitMsg")))]),s._v(" "),s.wireless?e("p",{staticClass:"fail"},[s._v(s._s(s.$t("complete.failer")))]):s._e()])]),s._v(" "),e("div",{ref:"con",staticClass:"form  width100",class:{formhas5G:!s.resultData.ssid5g_ssid},attrs:{id:"content"}},[e("Subtitle",{attrs:{name:s.$t("complete.name")}}),s._v(" "),e("div",{staticClass:"wifi_item"},[1==s.resultData.bsd?e("Subtitle",{attrs:{name:s.$t("complete.wifiTit")}}):s._e(),s._v(" "),1==s.resultData.bsd?e("p",[e("span",[s._v("2.4G")]),s._v(" "),e("span",{staticClass:"item2"},[s._v("5G")]),s._v("  Wi-Fi")]):e("p",[e("span",[s._v("2.4G")]),s._v("  Wi-Fi")]),s._v(" "),e("h3",[s._v(s._s(s.resultData.ssid2g_ssid))]),s._v(" "),e("p",[s._v(s._s(s.$t("dhcp.wifi_pass")))]),s._v(" "),e("h3",{class:"sa"===s.common.getCookie("lang")?"saText":""},[s._v(s._s(s.resultData.ssid2g_passwd))])],1),s._v(" "),s.resultData.ssid5g_ssid&&0==s.resultData.bsd?e("div",{staticClass:"wifi_item wifi_item2"},[s._m(0),s._v(" "),e("h3",[s._v(s._s(s.resultData.ssid5g_ssid))]),s._v(" "),e("p",[s._v(s._s(s.$t("dhcp.wifi_pass")))]),s._v(" "),e("h3",{class:"sa"===s.common.getCookie("lang")?"saText":""},[s._v(s._s(s.resultData.ssid5g_passwd))])]):s._e(),s._v(" "),e("div",{staticClass:"wifi_item3"},[e("p",{directives:[{name:"show",rawName:"v-show",value:!s.wireless,expression:"!wireless"}]},[s._v(s._s(s.$t("MANAGER"))+"：  "+s._s(s.resultData.lan_ip))]),s._v(" "),e("p",[s._v(s._s(s.$t("PASSWORD"))+"：  "),e("span",{class:"sa"===s.common.getCookie("lang")?"saText":""},[s._v(s._s(s.adminPassword))])]),s._v(" "),e("p",{directives:[{name:"show",rawName:"v-show",value:s.wireless,expression:"wireless"}]},[s._v(s._s(s.$t("complete.setApp")))])])],1)])},staticRenderFns:[function(){var s=this.$createElement,t=this._self._c||s;return t("p",[t("span",[this._v("5G")]),this._v("  Wi-Fi")])}]};var l=e("VU/8")(i,r,!1,function(s){e("P1wg")},"data-v-12541beb",null);t.default=l.exports}});