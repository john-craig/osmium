{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.mythoclast.gitea;
  serverSettings = cfg.settings.server or { };
  databaseSettings = cfg.settings.database or { };
  adminBootstrapMarker = "${cfg.stateDir}/.mythoclast-admin-bootstrap-complete";
  adminRotationState = "${cfg.stateDir}/.mythoclast-admin-rotation";
  identityDefinitions = lib.attrValues cfg.users;
  identityReconciliationEnabled = cfg.users != { } || cfg.organizations != { };
  adminCredentialFile = cfg.admin.passwordFile;
  adminRotationPasswordFile = if cfg.admin.rotation.passwordFile == null then "/dev/null" else cfg.admin.rotation.passwordFile;
  driftHistoryFile = "${cfg.stateDir}/.mythoclast-drift-history";
  driftReportFile = if cfg.driftDetection.reportFile == null then "" else cfg.driftDetection.reportFile;
  declaredDriftUsers = builtins.toJSON (lib.mapAttrsToList (_: user: {
    username = user.username;
    email = user.email;
  }) cfg.users);
  declaredDriftOrganizations = builtins.toJSON (lib.mapAttrsToList (_: organization: {
    name = organization.name;
    owner = organization.owner;
    description = organization.description;
    visibility = organization.visibility;
  }) cfg.organizations);
  exportFilter = pkgs.writeText "mythoclast-gitea-export-filter.jq" ''
    "# Generated Gitea configuration candidate; review before activation.",
    "# Export is read-only and does not adopt records.",
    "",
    "users = {",
    (.candidates[] | select(.resource == "user") |
      ("  " + .key + " = { username = " + (.username | @json) + "; email = " + (.email | @json) + "; full_name = " + (.full_name | @json) + "; website = " + (.website | @json) + "; location = " + (.location | @json) + "; passwordFile = builtins.throw " + ("Fill in passwordFile for " + .username + " before activation" | @json) + "; };") ),
    "};",
    "",
    "organizations = {",
    (.candidates[] | select(.resource == "organization") |
      "  " + .key + " = { name = " + (.name | @json) + "; description = " + (.description | @json) + "; visibility = " + (.visibility | @json) + "; owner = " + (.owner | @json) + "; };") ,
    "};"
  '';
  exportScript = pkgs.writeShellScriptBin "mythoclast-gitea-export" ''
    set -eu

    input=
    output=
    json=false
    selected_users=
    selected_orgs=

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --input)
          shift
          [ "$#" -gt 0 ] || { echo "--input requires a path" >&2; exit 2; }
          input=$1
          ;;
        --output)
          shift
          [ "$#" -gt 0 ] || { echo "--output requires a path" >&2; exit 2; }
          output=$1
          ;;
        --user)
          shift
          [ "$#" -gt 0 ] || { echo "--user requires a username" >&2; exit 2; }
          selected_users="''${selected_users}''${selected_users:+
}$1"
          ;;
        --organization)
          shift
          [ "$#" -gt 0 ] || { echo "--organization requires a name" >&2; exit 2; }
          selected_orgs="''${selected_orgs}''${selected_orgs:+
}$1"
          ;;
        --json) json=true ;;
        --adopt|--apply)
          echo "Export is review-only; adoption and activation are separate operations" >&2
          exit 2
          ;;
        *)
          echo "usage: mythoclast-gitea-export --input SNAPSHOT [--json] [--output PATH] [--user USERNAME] [--organization NAME]" >&2
          exit 2
          ;;
      esac
      shift
    done

    if [ -z "$input" ] || [ ! -r "$input" ]; then
      echo "--input must name a readable sanitized drift snapshot" >&2
      exit 2
    fi

    selected=$(${pkgs.jq}/bin/jq -cn \
      --arg users "$selected_users" --arg orgs "$selected_orgs" \
      '{users: ($users | split("\n") | map(select(length > 0))), organizations: ($orgs | split("\n") | map(select(length > 0)))}')

    report=$(${pkgs.jq}/bin/jq -c \
      --argjson selected "$selected" \
      'if ((.users | type) != "array" or (.organizations | type) != "array") then
         error("input must contain users and organizations arrays")
       else
         def selected($kind; $name):
           (($selected[$kind] | length) == 0 or (($selected[$kind] | index($name)) != null));
         def safe_name: test("^[A-Za-z0-9._-]+$");
         def source_is_external:
           ((.source // .login_source // .authentication_source // "") as $source |
            ($source != "" and ($source | ascii_downcase) != "local" and ($source | ascii_downcase) != "internal"));
         def key($prefix; $name):
           ($name | ascii_downcase | gsub("[^a-z0-9]+"; "_") | gsub("^_+|_+$"; "")) as $safe |
           ($prefix + "_" + $safe);
         def user_base:
           {username: (.username // .login // ""), email: (.email // ""), full_name: (.full_name // ""), website: (.website // ""), location: (.location // ""), admin: (.admin // .is_admin // false), source: (.source // .login_source // .authentication_source // "")};
         def org_base:
           {name: (.name // .username // ""), description: (.description // ""), visibility: (.visibility // ""), owner: (.owner // "")};
         (.users | map(select(selected("users"; (.username // .login // ""))) | user_base)) as $users |
         (.organizations | map(select(selected("organizations"; (.name // .username // ""))) | org_base)) as $orgs |
         ([ $users[] | select(.username != "") | key("user"; .username) ] + [ $orgs[] | select(.name != "") | key("organization"; .name) ]) as $keys |
         ($keys | group_by(.) | map(select(length > 1) | .[0])) as $colliding_keys |
         ([
           $users[] |
           if .username == "" then {kind: "excluded", resource: "user", reason_code: "missing-identity", explanation: "User has no stable username"}
           elif (.username | safe_name) | not then {kind: "excluded", resource: "user", username: .username, reason_code: "unsafe-name", explanation: "Username is not safe for a declaration key"}
           elif (.admin // false) then {kind: "excluded", resource: "user", username: .username, reason_code: "administrator-account", explanation: "Administrator accounts require explicit manual handling"}
           elif source_is_external then {kind: "excluded", resource: "user", username: .username, reason_code: "external-identity-provider", explanation: "External identity-provider records are not adoptable"}
           elif ((key("user"; .username) as $key | $colliding_keys | index($key)) != null) then {kind: "excluded", resource: "user", username: .username, reason_code: "duplicate-declaration-key", explanation: "Identity-derived declaration key collides with another record"}
           else {kind: "candidate", resource: "user", key: key("user"; .username), username: .username, email: .email, full_name: .full_name, website: .website, location: .location, password_file_required: true}
           end
         ] + [
           $orgs[] |
           if .name == "" then {kind: "excluded", resource: "organization", reason_code: "missing-identity", explanation: "Organization has no stable name"}
           elif (.name | safe_name) | not then {kind: "excluded", resource: "organization", name: .name, reason_code: "unsafe-name", explanation: "Organization name is not safe for a declaration key"}
           elif ((key("organization"; .name) as $key | $colliding_keys | index($key)) != null) then {kind: "excluded", resource: "organization", name: .name, reason_code: "duplicate-declaration-key", explanation: "Identity-derived declaration key collides with another record"}
            elif .owner == "" then {kind: "excluded", resource: "organization", name: .name, reason_code: "ambiguous-owner", explanation: "Organization owner is missing or ambiguous"}
            else (.owner) as $owner | if ([ $users[] | select(.username == $owner) ] | length) != 1 then {kind: "excluded", resource: "organization", name: .name, owner: $owner, reason_code: "ownership-conflict", explanation: "Organization owner does not map to exactly one observed user"}
            else {kind: "candidate", resource: "organization", key: key("organization"; .name), name: .name, description: .description, visibility: .visibility, owner: (key("user"; $owner))}
            end
            end
         ]) | sort_by([.kind, .resource, (.username // .name // ""), (.reason_code // "")]) as $records |
          {schema_version: 1, candidates: [$records[] | select(.kind == "candidate")], exclusions: [$records[] | select(.kind == "excluded")]} end' "$input") || {
      echo "Input is not a valid sanitized drift snapshot" >&2
      exit 2
    }

    if [ "$json" = true ]; then
      rendered=$report
    else
      rendered=$(${pkgs.jq}/bin/jq -r -f ${exportFilter} <<<"$report")
    fi

    if [ -n "$output" ]; then
      if [ ! -d "$(dirname "$output")" ]; then
        mkdir -p "$(dirname "$output")"
      fi
      tmp_output=$(mktemp "''${output}.XXXXXX")
      trap 'rm -f "$tmp_output"' EXIT
      printf '%s\n' "$rendered" > "$tmp_output"
      chmod 0640 "$tmp_output"
      mv "$tmp_output" "$output"
    else
      printf '%s\n' "$rendered"
    fi
  '';
  driftScript = pkgs.writeShellScriptBin "mythoclast-gitea-drift" ''
    set -eu

    api="http://127.0.0.1:${toString cfg.httpPort}/api/v1"
    admin_username=${lib.escapeShellArg cfg.admin.username}
    admin_password_file=${lib.escapeShellArg adminCredentialFile}
    output=""
    json=false
    check=false

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) json=true ;;
        --check) check=true ;;
        --output)
          shift
          [ "$#" -gt 0 ] || { echo "--output requires a path" >&2; exit 2; }
          output=$1
          ;;
        *) echo "usage: mythoclast-gitea-drift [--check] [--json] [--output PATH]" >&2; exit 2 ;;
      esac
      shift
    done

    if [ ! -s "$admin_password_file" ]; then
      echo "Gitea drift detection administrator credential file is empty or unavailable" >&2
      exit 2
    fi
    admin_password=$(cat "$admin_password_file")
    [ -n "$admin_password" ] || { echo "Gitea drift detection administrator credential is empty" >&2; exit 2; }
    if [ -s ${lib.escapeShellArg adminRotationPasswordFile} ]; then
      admin_password=$(cat ${lib.escapeShellArg adminRotationPasswordFile})
    fi

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT
    users_file="$tmp_dir/users.json"
    orgs_file="$tmp_dir/orgs.json"
    printf '[]' > "$users_file"
    printf '[]' > "$orgs_file"

    collect_pages() {
      endpoint=$1
      target=$2
      page=1
      while :; do
        response="$(${pkgs.curl}/bin/curl --fail --silent --show-error --user "$admin_username:$admin_password" \
          "$api/$endpoint?limit=50&page=$page")" || return 1
        ${pkgs.jq}/bin/jq -e 'type == "array"' >/dev/null <<<"$response" || return 1
        ${pkgs.jq}/bin/jq -s '.[0] + .[1]' "$target" <(${pkgs.jq}/bin/jq -c '.' <<<"$response") > "$target.next"
        mv "$target.next" "$target"
        count=$(${pkgs.jq}/bin/jq 'length' <<<"$response")
        [ "$count" -lt 50 ] && break
        page=$((page + 1))
      done
    }

    if ! collect_pages "admin/users" "$users_file" || ! collect_pages "admin/orgs" "$orgs_file"; then
      error_report=$(${pkgs.jq}/bin/jq -cn \
        --arg error "Unable to collect a complete read-only Gitea identity snapshot" \
        '{schema_version: 1, status: "operational-error", errors: [$error], classifications: []}')
      if [ -n "$output" ]; then
        install -d -m 0750 "$(dirname "$output")"
        printf '%s\n' "$error_report" > "$output"
      else
        printf '%s\n' "$error_report"
      fi
      exit 2
    fi

    users=$(${pkgs.jq}/bin/jq -c '[.[] | {
      username: (.login // .username // ""),
      email: (.email // ""),
      admin: (.is_admin // .isAdmin // false),
      full_name: (.full_name // ""),
      website: (.website // ""),
      location: (.location // "")
    }] | sort_by(.username)' "$users_file")
    organizations=$(${pkgs.jq}/bin/jq -c '[.[] | {
      name: (.username // .name // ""),
      description: (.description // ""),
      visibility: (.visibility // ""),
      owner: (.owner.login // .owner.username // .owner // "")
    }] | sort_by(.name)' "$orgs_file")
    desired_users=${lib.escapeShellArg declaredDriftUsers}
    desired_orgs=${lib.escapeShellArg declaredDriftOrganizations}

    report=$(${pkgs.jq}/bin/jq -cn \
      --argjson observed_users "$users" \
      --argjson observed_orgs "$organizations" \
      --argjson desired_users "$desired_users" \
      --argjson desired_orgs "$desired_orgs" \
      --arg observed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      def user_fields: ["email"];
      def org_fields: ["description", "visibility", "owner"];
      def differences($observed; $desired; $fields):
        [$fields[] as $field | select(($observed[$field] // "") != ($desired[$field] // "")) |
          {field: $field, observed: ($observed[$field] // ""), declared: ($desired[$field] // "")}];
      def user_classifications:
        [$observed_users[] as $observed |
          ($desired_users | map(select(.username == $observed.username)) | first) as $desired |
          if $desired == null then
            {kind: (if $observed.admin then "administrator-conflict" else "unmanaged" end), resource: "user", username: $observed.username, observed: $observed}
          elif $observed.admin then
            {kind: "administrator-conflict", resource: "user", username: $observed.username, observed: $observed}
          else
            (differences($observed; $desired; user_fields)) as $differences |
            {kind: (if $differences == [] then "matching" else "changed" end), resource: "user", username: $observed.username, differences: $differences}
          end] +
        [$desired_users[] as $desired | select(($observed_users | map(select(.username == $desired.username))) == []) |
          {kind: "missing", resource: "user", username: $desired.username, declared: $desired}];
      def org_classifications:
        [$observed_orgs[] as $observed |
          ($desired_orgs | map(select(.name == $observed.name)) | first) as $desired |
          if $desired == null then
            {kind: "unmanaged", resource: "organization", name: $observed.name, observed: $observed}
          else
            (differences($observed; $desired; org_fields)) as $differences |
            {kind: (if $differences == [] then "matching" elif ([$differences[].field] | index("owner")) != null then "ownership-conflict" else "changed" end), resource: "organization", name: $observed.name, differences: $differences}
          end] +
        [$desired_orgs[] as $desired | select(($observed_orgs | map(select(.name == $desired.name))) == []) |
          {kind: "missing", resource: "organization", name: $desired.name, declared: $desired}];
      (user_classifications + org_classifications) as $classifications |
      {schema_version: 1, observed_at: $observed_at,
       status: (if ([$classifications[] | select(.kind != "matching")] | length) == 0 then "clean" else "drift" end),
       users: $observed_users, organizations: $observed_orgs, classifications: $classifications,
       errors: []}' )

    canonical=$(${pkgs.jq}/bin/jq -cS 'del(.observed_at)' <<<"$report")
    fingerprint=$(printf '%s' "$canonical" | sha256sum | cut -d ' ' -f 1)
    history=${lib.escapeShellArg driftHistoryFile}
    if ${lib.boolToString cfg.driftDetection.persistHistory}; then
      tmp_history=$(mktemp "''${history}.XXXXXX")
      trap 'rm -rf "$tmp_dir" "$tmp_history"' EXIT
      ${pkgs.jq}/bin/jq -cn \
        --arg fingerprint "$fingerprint" \
        --arg observed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schema_version: 1, fingerprint: $fingerprint, observed_at: $observed_at}' > "$tmp_history"
      chmod 0640 "$tmp_history"
      mv "$tmp_history" "$history"
    fi

    if [ -n "$output" ]; then
      install -d -m 0750 "$(dirname "$output")"
      printf '%s\n' "$report" > "$output"
    elif [ -n ${lib.escapeShellArg driftReportFile} ]; then
      install -d -m 0750 "$(dirname ${lib.escapeShellArg driftReportFile})"
      printf '%s\n' "$report" > ${lib.escapeShellArg driftReportFile}
    fi

    if [ "$json" = true ] || [ "$check" = false ]; then
      printf '%s\n' "$report"
    else
      ${pkgs.jq}/bin/jq -r '
        "Gitea drift report: " + .status,
        (.classifications[] | select(.kind != "matching") |
          "- " + .kind + " " + .resource + " " + (.username // .name))' <<<"$report"
    fi

    if [ "$check" = true ] && [ "$(${pkgs.jq}/bin/jq '[.classifications[] | select(.kind != "matching")] | length' <<<"$report")" -gt 0 ]; then
      exit 1
    fi
  '';
  userReconciliation = lib.concatMapStringsSep "\n" (name:
    let
      user = cfg.users.${name};
      state = "${cfg.stateDir}/.mythoclast-user-${name}";
    in
    ''
      user_password=$(cat ${lib.escapeShellArg user.passwordFile})
      if [ -z "$user_password" ]; then
        echo "Gitea user password file for ${lib.escapeShellArg user.username} is empty" >&2
        exit 1
      fi
      user_status=$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' --user "$admin_username:$admin_password" \
        "http://127.0.0.1:${toString cfg.httpPort}/api/v1/users/${lib.escapeShellArg user.username}")
      case "$user_status" in
        200) ;;
        404)
          ${pkgs.gitea}/bin/gitea --config ${lib.escapeShellArg "${cfg.stateDir}/custom/conf/app.ini"} admin user create \
            --username ${lib.escapeShellArg user.username} --password "$user_password" \
            --email ${lib.escapeShellArg user.email} --must-change-password=false
          ;;
        *)
          echo "Unable to inspect declared Gitea user ${lib.escapeShellArg user.username} (HTTP $user_status)" >&2
          exit 1
          ;;
      esac
      user_payload="$(${pkgs.jq}/bin/jq -cn \
        --arg login_name ${lib.escapeShellArg user.username} \
        --arg email ${lib.escapeShellArg user.email} \
        '{login_name: $login_name, email: $email, admin: false, must_change_password: false}')"
      ${pkgs.curl}/bin/curl --fail --silent --show-error --user "$admin_username:$admin_password" \
        -X PATCH "http://127.0.0.1:${toString cfg.httpPort}/api/v1/admin/users/${lib.escapeShellArg user.username}" \
        -H 'Content-Type: application/json' --data "$user_payload" >/dev/null
      user_salt=
      user_hash=
      if [ -f ${lib.escapeShellArg state} ]; then
        while IFS='=' read -r key value; do
          case "$key" in
            salt) user_salt=$value ;;
            applied_hash) user_hash=$value ;;
          esac
        done < ${lib.escapeShellArg state}
      fi
      if [ -z "$user_salt" ]; then
        user_salt=$(head -c 32 /dev/urandom | base64 -w 0)
      fi
      candidate_hash=$(printf '%s%s' "$user_salt" "$user_password" | sha256sum | cut -d ' ' -f 1)
      if [ "$candidate_hash" != "$user_hash" ]; then
        ${pkgs.gitea}/bin/gitea --config ${lib.escapeShellArg "${cfg.stateDir}/custom/conf/app.ini"} admin user change-password \
          --username ${lib.escapeShellArg user.username} --password "$user_password" \
          --must-change-password=false
        user_tmp=$(mktemp ${lib.escapeShellArg "${state}.XXXXXX"})
        trap 'rm -f "$user_tmp"' EXIT
        printf 'salt=%s\napplied_hash=%s\n' "$user_salt" "$candidate_hash" > "$user_tmp"
        chmod 0640 "$user_tmp"
        mv "$user_tmp" ${lib.escapeShellArg state}
        trap - EXIT
      fi
    '') (lib.attrNames cfg.users);
  organizationReconciliation = lib.concatMapStringsSep "\n" (name:
    let
      organization = cfg.organizations.${name};
      owner = lib.findFirst (user: user.username == organization.owner) null identityDefinitions;
      ownerPasswordFile = if owner == null then "/dev/null" else owner.passwordFile;
    in
    ''
      owner_password=$(cat ${lib.escapeShellArg ownerPasswordFile})
      if [ -z "$owner_password" ]; then
        echo "Gitea owner password file for ${lib.escapeShellArg organization.owner} is empty" >&2
        exit 1
      fi
      organization_status=$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' \
        --user ${lib.escapeShellArg organization.owner}:"$owner_password" \
        "http://127.0.0.1:${toString cfg.httpPort}/api/v1/orgs/${lib.escapeShellArg organization.name}")
      organization_payload="$(${pkgs.jq}/bin/jq -cn \
        --arg username ${lib.escapeShellArg organization.name} \
        --arg description ${lib.escapeShellArg organization.description} \
        --arg visibility ${lib.escapeShellArg organization.visibility} \
        '{username: $username, description: $description, visibility: $visibility}')"
      case "$organization_status" in
        200)
          ${pkgs.curl}/bin/curl --fail --silent --show-error \
            --user ${lib.escapeShellArg organization.owner}:"$owner_password" \
            -X PATCH "http://127.0.0.1:${toString cfg.httpPort}/api/v1/orgs/${lib.escapeShellArg organization.name}" \
            -H 'Content-Type: application/json' --data "$organization_payload" >/dev/null
          ;;
        404)
          ${pkgs.curl}/bin/curl --fail --silent --show-error \
            --user ${lib.escapeShellArg organization.owner}:"$owner_password" \
            -X POST "http://127.0.0.1:${toString cfg.httpPort}/api/v1/orgs" \
            -H 'Content-Type: application/json' --data "$organization_payload" >/dev/null
          ;;
        *)
          echo "Unable to inspect declared Gitea organization ${lib.escapeShellArg organization.name} (HTTP $organization_status)" >&2
          exit 1
          ;;
      esac
    '') (lib.attrNames cfg.organizations);
in
{
  options.services.mythoclast.gitea = {
    enable = lib.mkEnableOption "the Mythoclast Gitea service";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/gitea";
      description = "Directory containing all Gitea application state.";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Guest TCP port for the Gitea HTTP server.";
    };

    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Guest TCP port for the Gitea SSH server.";
    };

    hostHttpPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Host TCP port forwarded to the Gitea HTTP server.";
    };

    hostSshPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Host TCP port forwarded to the Gitea SSH server.";
    };

    databasePasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional file containing the Gitea database password.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional declarative settings for Gitea.";
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          username = lib.mkOption {
            type = lib.types.str;
            description = "Stable Gitea username for this non-admin identity.";
          };
          email = lib.mkOption {
            type = lib.types.str;
            description = "Email address for this non-admin Gitea user.";
          };
          passwordFile = lib.mkOption {
            type = lib.types.path;
            description = "Runtime file containing this user's password.";
          };
        };
      }));
      default = { };
      description = "Declarative non-administrator Gitea users.";
    };

    organizations = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Stable Gitea organization name.";
          };
          owner = lib.mkOption {
            type = lib.types.str;
            description = "Username of the declared organization owner.";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Description for the Gitea organization.";
          };
          visibility = lib.mkOption {
            type = lib.types.enum [ "public" "limited" "private" ];
            default = "private";
            description = "Visibility of the Gitea organization.";
          };
        };
      }));
      default = { };
      description = "Declarative Gitea organizations owned by declared users.";
    };

    driftDetection = {
      enable = lib.mkEnableOption "read-only Gitea identity drift detection";

      reportFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional path for the latest machine-readable drift report.";
      };

      persistHistory = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Persist a sanitized fingerprint and timestamp for the latest observation.";
      };

      runAtStartup = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run a read-only drift check after Gitea starts.";
      };

      timer = {
        enable = lib.mkEnableOption "periodic Gitea identity drift detection";

        interval = lib.mkOption {
          type = lib.types.str;
          default = "1h";
          description = "Systemd calendar interval for periodic drift checks.";
        };
      };
    };

    reverseConfiguration = {
      enable = lib.mkEnableOption "review-only Gitea configuration candidate export";
    };

    admin = {
      enable = lib.mkEnableOption "the initial Gitea administrator bootstrap";

      username = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Username for the initial Gitea administrator.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "admin@localhost";
        description = "Email address for the initial Gitea administrator.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Runtime file containing the initial administrator password.";
      };

      rotation = {
        enable = lib.mkEnableOption "automatic Gitea administrator credential rotation";

        passwordFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Runtime file containing the desired replacement administrator password.";
        };

        maxAge = lib.mkOption {
          type = lib.types.ints.positive;
          default = 90 * 24 * 60 * 60;
          description = "Maximum administrator credential age in seconds.";
        };

        checkInterval = lib.mkOption {
          type = lib.types.ints.positive;
          default = 60 * 60;
          description = "Interval between administrator credential rotation checks in seconds.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.stateDir;
        message = "services.mythoclast.gitea.stateDir must be below /var/lib.";
      }
      {
        assertion = cfg.hostHttpPort != cfg.hostSshPort;
        message = "Gitea HTTP and SSH host ports must be different.";
      }
      {
        assertion = !cfg.admin.enable || cfg.admin.passwordFile != null;
        message = "services.mythoclast.gitea.admin.passwordFile is required when administrator bootstrap is enabled.";
      }
      {
        assertion = !cfg.admin.rotation.enable || cfg.admin.enable;
        message = "Gitea administrator credential rotation requires administrator bootstrap to be enabled.";
      }
      {
        assertion = !cfg.admin.rotation.enable || cfg.admin.rotation.passwordFile != null;
        message = "services.mythoclast.gitea.admin.rotation.passwordFile is required when credential rotation is enabled.";
      }
      {
        assertion = !identityReconciliationEnabled || cfg.admin.enable;
        message = "Declarative Gitea users and organizations require administrator bootstrap to be enabled.";
      }
      {
        assertion = !identityReconciliationEnabled || adminCredentialFile != null;
        message = "Declarative Gitea users and organizations require an administrator credential file.";
      }
      {
        assertion = !cfg.driftDetection.enable || cfg.admin.enable;
        message = "Gitea drift detection requires administrator bootstrap to be enabled.";
      }
      {
        assertion = !cfg.driftDetection.enable || adminCredentialFile != null;
        message = "Gitea drift detection requires an administrator credential file.";
      }
      {
        assertion = lib.length (lib.unique (map (user: user.username) identityDefinitions)) == lib.length identityDefinitions;
        message = "Declarative Gitea user usernames must be unique.";
      }
      {
        assertion = lib.all (user: user.username != cfg.admin.username) identityDefinitions;
        message = "Declarative Gitea users must not use the administrator username.";
      }
      {
        assertion = lib.all (user: builtins.match "[A-Za-z0-9._-]+" user.username != null) identityDefinitions;
        message = "Declarative Gitea usernames may contain only letters, numbers, dots, underscores, and hyphens.";
      }
      {
        assertion = lib.all (organization:
          builtins.match "[A-Za-z0-9._-]+" organization.name != null
          && lib.any (user: user.username == organization.owner) identityDefinitions
        ) (lib.attrValues cfg.organizations);
        message = "Declarative Gitea organizations require safe names and declared user owners.";
      }
    ];

    users.users.gitea = {
      uid = 992;
      isSystemUser = true;
      group = "gitea";
      home = cfg.stateDir;
      createHome = true;
    };
    users.groups.gitea.gid = 992;

    environment.systemPackages = lib.mkIf (cfg.driftDetection.enable || cfg.reverseConfiguration.enable) [ driftScript exportScript ];

    services.gitea = {
      enable = true;
      user = "gitea";
      group = "gitea";
      stateDir = cfg.stateDir;
      database = {
        type = "sqlite3";
        path = "${cfg.stateDir}/data/gitea.db";
      } // lib.optionalAttrs (cfg.databasePasswordFile != null) {
        passwordFile = cfg.databasePasswordFile;
      };
      settings = cfg.settings // {
        server = serverSettings // {
          HTTP_ADDR = "0.0.0.0";
          HTTP_PORT = cfg.httpPort;
          SSH_PORT = cfg.sshPort;
        };
        database = databaseSettings // {
          DB_TYPE = "sqlite3";
          PATH = "${cfg.stateDir}/data/gitea.db";
        };
      };
    };

    environment.persistence."/persistent".directories = [
      {
        directory = cfg.stateDir;
        user = "gitea";
        group = "gitea";
        mode = "0750";
      }
    ];

    systemd.services.mythoclast-gitea-admin-bootstrap = lib.mkIf cfg.admin.enable {
      description = "Bootstrap the Mythoclast Gitea administrator";
      wantedBy = [ "multi-user.target" ];
      after = [ "gitea.service" ];
      requires = [ "gitea.service" ];
      unitConfig.ConditionPathExists = "!${adminBootstrapMarker}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "gitea";
        Group = "gitea";
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "mythoclast-gitea-admin-bootstrap" ''
          set -eu
          password=$(cat ${lib.escapeShellArg cfg.admin.passwordFile})
          ${pkgs.gitea}/bin/gitea --config ${lib.escapeShellArg "${cfg.stateDir}/custom/conf/app.ini"} admin user create \
            --username ${lib.escapeShellArg cfg.admin.username} \
            --password "$password" \
            --email ${lib.escapeShellArg cfg.admin.email} \
            --admin \
            --must-change-password=false
          install -m 0640 /dev/null ${lib.escapeShellArg adminBootstrapMarker}
        '';
      };
    };

    systemd.services.mythoclast-gitea-admin-rotation = lib.mkIf cfg.admin.rotation.enable {
      description = "Rotate the Mythoclast Gitea administrator credential";
      wantedBy = [ "multi-user.target" ];
      after = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" "mythoclast-gitea-admin-rotation.service" ];
      requires = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "gitea";
        Group = "gitea";
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "mythoclast-gitea-admin-rotation" ''
          set -eu
          state=${lib.escapeShellArg adminRotationState}
          password_file=${lib.escapeShellArg cfg.admin.rotation.passwordFile}
          now=$(date +%s)
          password=$(cat "$password_file")
          if [ -z "$password" ]; then
            echo "Gitea administrator rotation password file is empty" >&2
            exit 1
          fi

          salt=
          applied_at=0
          applied_hash=
          if [ -f "$state" ]; then
            while IFS='=' read -r key value; do
              case "$key" in
                salt) salt=$value ;;
                applied_at) applied_at=$value ;;
                applied_hash) applied_hash=$value ;;
              esac
            done < "$state"
          fi

          if [ -z "$salt" ]; then
            salt=$(head -c 32 /dev/urandom | base64 -w 0)
          fi
          candidate_hash=$(printf '%s%s' "$salt" "$password" | sha256sum | cut -d ' ' -f 1)

          if [ "$candidate_hash" = "$applied_hash" ]; then
            if [ "$((now - applied_at))" -lt ${toString cfg.admin.rotation.maxAge} ]; then
              exit 0
            fi
            echo "Gitea administrator rotation is due, but the replacement credential is unchanged" >&2
            exit 1
          fi

          ${pkgs.gitea}/bin/gitea --config ${lib.escapeShellArg "${cfg.stateDir}/custom/conf/app.ini"} admin user change-password \
            --username ${lib.escapeShellArg cfg.admin.username} \
            --password "$password" \
            --must-change-password=false

          tmp=$(mktemp "''${state}.XXXXXX")
          trap 'rm -f "$tmp"' EXIT
          printf 'salt=%s\napplied_at=%s\napplied_hash=%s\n' "$salt" "$now" "$candidate_hash" > "$tmp"
          chmod 0640 "$tmp"
          mv "$tmp" "$state"
        '';
      };
    };

    systemd.timers.mythoclast-gitea-admin-rotation = lib.mkIf cfg.admin.rotation.enable {
      description = "Check the Mythoclast Gitea administrator credential age";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "${toString cfg.admin.rotation.checkInterval}s";
        OnUnitActiveSec = "${toString cfg.admin.rotation.checkInterval}s";
        Unit = "mythoclast-gitea-admin-rotation.service";
      };
    };

    system.activationScripts.mythoclast-gitea-admin-rotation = lib.mkIf cfg.admin.rotation.enable {
      text = ''
        ${pkgs.systemd}/bin/systemctl restart mythoclast-gitea-admin-rotation.service || true
      '';
    };

    systemd.services.mythoclast-gitea-identities = lib.mkIf identityReconciliationEnabled {
      description = "Reconcile declarative Mythoclast Gitea users and organizations";
      wantedBy = [ "multi-user.target" ];
      after = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" "mythoclast-gitea-admin-rotation.service" ];
      requires = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "gitea";
        Group = "gitea";
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "mythoclast-gitea-identities" ''
          set -eu
          admin_username=${lib.escapeShellArg cfg.admin.username}
          admin_password=$(cat ${lib.escapeShellArg adminCredentialFile})
          if [ -n "$admin_password" ] && [ -f ${lib.escapeShellArg adminRotationState} ]; then
            if [ ! -s ${lib.escapeShellArg adminRotationPasswordFile} ]; then
              echo "Skipping Gitea identity reconciliation until the rotated administrator credential is available"
              exit 0
            fi
          fi
          if [ -s ${lib.escapeShellArg adminRotationPasswordFile} ]; then
            admin_password=$(cat ${lib.escapeShellArg adminRotationPasswordFile})
          fi
          if [ -z "$admin_password" ]; then
            echo "Gitea administrator credential file is empty" >&2
            exit 1
          fi
          ${userReconciliation}
          ${organizationReconciliation}
        '';
      };
    };

    system.activationScripts.mythoclast-gitea-identities = lib.mkIf identityReconciliationEnabled {
      text = ''
        ${pkgs.systemd}/bin/systemctl restart mythoclast-gitea-identities.service || true
      '';
    };

    systemd.services.mythoclast-gitea-drift = lib.mkIf (cfg.driftDetection.enable && cfg.driftDetection.runAtStartup) {
      description = "Inspect Gitea identities for drift";
      wantedBy = [ "multi-user.target" ];
      after = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" ];
      requires = [ "gitea.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "gitea";
        Group = "gitea";
        UMask = "0077";
        ExecStart = "${driftScript}/bin/mythoclast-gitea-drift --json";
      };
    };

    systemd.services.mythoclast-gitea-drift-timer = lib.mkIf (cfg.driftDetection.enable && cfg.driftDetection.timer.enable) {
      description = "Inspect Gitea identities for scheduled drift";
      serviceConfig = {
        Type = "oneshot";
        User = "gitea";
        Group = "gitea";
        UMask = "0077";
        ExecStart = "${driftScript}/bin/mythoclast-gitea-drift --json";
      };
    };

    systemd.timers.mythoclast-gitea-drift = lib.mkIf (cfg.driftDetection.enable && cfg.driftDetection.timer.enable) {
      description = "Schedule Gitea identity drift inspection";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.driftDetection.timer.interval;
        OnUnitActiveSec = cfg.driftDetection.timer.interval;
        Unit = "mythoclast-gitea-drift-timer.service";
      };
    };

  } // lib.optionalAttrs (options ? microvm) {
    microvm.forwardPorts = [
      {
        from = "host";
        proto = "tcp";
        host.port = cfg.hostHttpPort;
        guest.port = cfg.httpPort;
      }
      {
        from = "host";
        proto = "tcp";
        host.port = cfg.hostSshPort;
        guest.port = cfg.sshPort;
      }
    ];
  });
}
