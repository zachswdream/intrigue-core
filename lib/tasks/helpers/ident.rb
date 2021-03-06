
module Intrigue
module Task
module Ident

  ###
  ### Use the issue factory to find vulnerasbility checks we can run 
  ### and kick them off
  ###
  def run_vuln_checks_from_fingerprint(fingerprint, entity)
  
    all_checks = []
    project = entity.project 

    fingerprint.each do |f|
      ### Get a list of actual vulnerability checks based on issues 
      vendor_string = f["vendor"]
      product_string = f["product"]

      _log "Getting checks for #{vendor_string} #{product_string}"
      checks_to_be_run = Intrigue::Issue::IssueFactory.checks_for_vendor_product(vendor_string, product_string)

      all_checks << checks_to_be_run
    end

    # handle nuclei, and cve checks here
    #
    all_checks.flatten.compact.uniq.each do |check|

      # if we want to pass check options based on some fingerprint crtieria
      check_options = []   

      # get the scan result id ... TODO, ideally we'd track this. 
      existing_scan_result_id = nil

      # start the task
      start_task("task_autoscheduled", project, existing_scan_result_id, check, entity, 1, check_options)
    end

  # return a list of checks
  all_checks.flatten.compact.uniq 
  end

  def create_issues_from_fingerprint_tags(fingerprint, entity)

    issues_to_create = []
    # iterate through the fingerprints and create
    # issues for each known tag
    fingerprint.each do |fp|
      next unless fp && fp["tags"]
      fp["tags"].each do |t|
        if t.match(/webcam/i)
          issues_to_create << ["exposed_webcam_interface", fp]
        elsif t.match(/DatabaseService/i)
          issues_to_create << ["exposed_database_service", fp]
        end
      end
    end

    issues_to_create.each do |i|
      _create_linked_issue i.first, i.last, entity
    end

  end

  ###
  ### Parse out, and fingerprint the individual components 
  ###
  def fingerprint_links(links, hostname)
    script_components = extract_and_fingerprint_links(links, hostname)
    
    ### Check for vulns in included scripts
    fingerprint = []
    if script_components.count > 0
      fingerprint.concat(add_vulns_by_cpe(script_components))
    end

  fingerprint
  end

  def extract_and_fingerprint_links(link_list, host)
    components = []
    link_list.each do |s|

      # skip anything that's not http
      next unless s.match(/^http/)

      begin 
        uri = URI.parse(s)
      rescue URI::InvalidURIError => e
        @task_result.logger.log "Unable to parse improperly formatted URI: #{s}"
        next # unable to parse 
      end

      next unless uri.host && uri.port && uri.scheme.match(/^http/)
      ### 
      ### Determine who's hosting
      ### 
      begin
        if uri.host.match(/#{host}/)
          host_location = "local"
        else
          host_location = "remote"
        end
      rescue URI::InvalidURIError => e
        host_location = "unknown"
      end

      ###
      ### Match it up with ident  
      ###
      ident_matches = generate_http_requests_and_check(s, {'only-check-base-url': true }) 
      js_fp_matches = ident_matches["fingerprint"].select{|x| x["tags"] && x["tags"].include?("Javascript") }

      if js_fp_matches.count > 0
        js_fp_matches.each do |m|
          components << m.merge({"uri" => s, "relative_host" =>  host_location })
        end
      else 
        # otherwise, we didnt find it, so just stick in a url withoout a name / version
        components << {"uri" => s, "relative_host" =>  host_location }
      end
    end
  
  components.compact
  end

  def fingerprint_service(ip_address,port=nil, proto="TCP")

    # Use intrigue-ident code to request fingerprint
    ident_matches = nil

    ###
    ### Go through each known port
    ###
    if port == 21
      ident_matches = generate_ftp_request_and_check(ip_address) || {}
    end
      
    if (port == 22 || port == 2222)
      ident_matches = generate_ssh_request_and_check(ip_address) || {}
    end
      
    if port == 23
      ident_matches = generate_telnet_request_and_check(ip_address) || {}
    end

    if (port == 25 || port == 587)
      ident_matches = generate_smtp_request_and_check(ip_address) || {}
    end
    
    if port == 53
      ident_matches = generate_dns_request_and_check(ip_address) || {}
    end
    
    if port == 6379 
      ident_matches = generate_redis_request_and_check(ip_address) || {}
    end

    if port == 161
      ident_matches = generate_snmp_request_and_check(ip_address) || {}
    end

    if port == 3306
      ident_matches = generate_mysql_request_and_check(ip_address) || {}
    end
    
    ###
    ### But default to HTTP through each known port
    ###
    if ident_matches
      return ident_matches # return right away if we a FP 
    else
      url = "http://#{ip_address}:#{port}" 
      ident_matches = generate_http_requests_and_check(url) || {}

      # if we didnt fail, pull out the FP and match to vulns
      ident_fingerprints = ident_matches["fingerprint"] || []
      
      # add vulns to the fingerprint
      if ident_fingerprints.count > 0
        ident_fingerprints = add_vulns_by_cpe(ident_fingerprints)
      end    
      
      # merge them 
      out = ident_matches.merge({"fingerprint" => ident_fingerprints})

    end
   
  out 
  end
  
  def fingerprint_url(url)
     ###
    ### But default to HTTP through each known port
    ###
    ident_matches = generate_http_requests_and_check(url) || {} 
    
    # okay we failed
    return unless ident_matches

    # if we didnt fail, pull out the FP and match to vulns
    ident_fingerprints = ident_matches["fingerprint"] || []
    if ident_fingerprints.count > 0
      ident_fingerprints = add_vulns_by_cpe(ident_fingerprints)
    end
  
  ident_matches.merge({"fingerprint" => ident_fingerprints})
  end


end
end
end