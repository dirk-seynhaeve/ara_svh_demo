#!/bin/bash

# Get Git's short hash length
SHORT_LEN=$(git config --get core.abbrev 2>/dev/null || git rev-parse --short HEAD 2>/dev/null | wc -c)
SHORT_LEN=$((SHORT_LEN - 1))
: ${SHORT_LEN:=7}

git submodule status --recursive | gawk -v short_len="$SHORT_LEN" '
BEGIN {
  COLOR_GREEN = "\033[32m"
  COLOR_YELLOW = "\033[33m"
  COLOR_RED = "\033[31m"
  COLOR_MAGENTA = "\033[35m"
  COLOR_CYAN = "\033[36m"
  COLOR_BOLD_WHITE = "\033[1;37m"
  COLOR_GRAY = "\033[90m"
  COLOR_RESET = "\033[0m"

  print "Legend:"
  print "  " COLOR_GREEN "[ ]" COLOR_RESET " checked out correctly"
  print "  " COLOR_YELLOW "[+]" COLOR_RESET " not at expected commit"
  print "  " COLOR_RED "[-]" COLOR_RESET " not checked out"
  print "  " COLOR_MAGENTA "[U]" COLOR_RESET " unresolvedconflict"
  print ""
}

function get_status_display(status_char) {
  if (status_char == " ") {
    return COLOR_GREEN "[ ]" COLOR_RESET
  } else if (status_char == "+") {
    return COLOR_YELLOW "[+]" COLOR_RESET
  } else if (status_char == "-") {
    return COLOR_RED "[-]" COLOR_RESET
  } else if (status_char == "U") {
    return COLOR_MAGENTA "[U]" COLOR_RESET
  } else {
    return "[" status_char "]"
  }
}

function print_tree(node, prefix, curr_depth,    item_list, item_cnt, dir, i, items, idx, item, type, path, mark, n, parts, name, new_prefix, prefix_display_width, name_width, target_col, status_display) {
  item_list = ""
  item_cnt = 0

  for (dir in all_dirs) {
    if (parents[dir] == node) {
      item_cnt++
      item_list = item_list (item_list == "" ? "" : "|") "D:" dir
    }
  }

  for (i = 1; i <= sub_count; i++) {
    if (parents[submodules[i]] == node) {
      item_cnt++
      item_list = item_list (item_list == "" ? "" : "|") "S:" submodules[i]
    }
  }

  if (item_cnt == 0) return

  split(item_list, items, "|")

  for (idx = 1; idx <= item_cnt; idx++) {
    item = items[idx]
    type = substr(item, 1, 1)
    path = substr(item, 3)

    mark = (idx < item_cnt ? "├── " : "└── ")

    n = split(path, parts, "/")
    name = parts[n]

    if (type == "D") {
      printf "%s%s%s%s%s/\n", prefix, mark, COLOR_GRAY, name, COLOR_RESET
    } else {
      status_display = get_status_display(statuses[path])

      prefix_display_width = curr_depth * 4 + 4 + 4
      target_col = max_prefix_width + maxLeafLen
      name_width = target_col - prefix_display_width
      printf "%s%s%s %s%-*s%s (%s%s%s)\n", prefix, mark, status_display, COLOR_BOLD_WHITE, name_width, leaves[path], COLOR_RESET, COLOR_CYAN, shas[path], COLOR_RESET
    }    new_prefix = prefix ((idx < item_cnt) ? "│   " : "    ")
    print_tree(path, new_prefix, curr_depth + 1)
  }
}

{
  status = substr($0, 1, 1)
  sha = $1
  path = $2

  n = split(path, parts, "/")
  leaf = parts[n]

  leaf_len = length(leaf)
  if (leaf_len > maxLeafLen) {
    maxLeafLen = leaf_len
  }

  submodules[++sub_count] = path
  leaves[path] = leaf
  statuses[path] = status
  shas[path] = substr(sha, 1, short_len)

  if (n == 1) {
    parents[path] = ""
    depth[path] = 0
  } else {
    parents[path] = parts[1]
    for (i = 2; i < n; i++)
      parents[path] = parents[path] "/" parts[i]
    depth[path] = n - 1
  }

  if (depth[path] > max_depth) {
    max_depth = depth[path]
  }

  temp = parents[path]
  while (temp != "") {
    if (!(temp in all_dirs)) {
      all_dirs[temp] = 1

      m = split(temp, tparts, "/")
      if (m == 1) {
        parents[temp] = ""
      } else {
        parents[temp] = tparts[1]
        for (j = 2; j < m; j++)
          parents[temp] = parents[temp] "/" tparts[j]
      }
    }
    temp = parents[temp]
  }
}

END {
  max_prefix_width = max_depth * 4 + 4 + 4
  print_tree("", "", 0)
}
'
