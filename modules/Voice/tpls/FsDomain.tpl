<include>
<domain name="default.local">
  <params></params>
  <variables>
    <variable name="record_stereo" value="true"/>
    <variable name="default_gateway" value="$${default_provider}"/>
    <variable name="default_areacode" value="$${default_areacode}"/>
    <variable name="transfer_fallback_extension" value="operator"/>
    <variable name="export_vars" value="domain_name"/>
  </variables>
  <groups><group name="default.local">
    <users>
      <X-PRE-PROCESS cmd="include" data="default.local/*.xml"/>
    </users>
    </group></groups>
</domain>
</include>