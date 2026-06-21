module ApplicationHelper
  def app_shell(active:, dependent: nil, &block)
    render(
      partial: "shared/app_shell",
      locals: {
        active: active.to_sym,
        dependent: dependent,
        content: capture(&block)
      }
    )
  end

  def paperbridge_logo(width: 160, height: 56, class_name: nil)
    class_attr = class_name.present? ? %( class="#{ERB::Util.html_escape(class_name)}") : ""

    <<~SVG.html_safe
      <svg#{class_attr} width="#{width}" height="#{height}" viewBox="0 0 900 320" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="PaperBridge">
        <g transform="translate(320,35)">
          <path d="M0 90C45 35 155 35 200 90" stroke="#1e3a8a" stroke-width="10" stroke-linecap="round"></path>
          <path d="M-10 55C50 0 150 0 210 55" stroke="#1e3a8a" stroke-width="10" stroke-linecap="round"></path>
          <line x1="30" y1="40" x2="30" y2="90" stroke="#1e3a8a" stroke-width="10" stroke-linecap="round"></line>
          <line x1="100" y1="18" x2="100" y2="72" stroke="#1e3a8a" stroke-width="10" stroke-linecap="round"></line>
          <line x1="170" y1="40" x2="170" y2="90" stroke="#1e3a8a" stroke-width="10" stroke-linecap="round"></line>
        </g>
        <text x="450" y="190" text-anchor="middle" font-family="Georgia, serif" font-size="72" fill="#1e3a8a">PaperBridge</text>
        <text x="450" y="245" text-anchor="middle" font-family="Inter, sans-serif" font-size="28" fill="#4b5563">Organize. Understand. Advocate.</text>
      </svg>
    SVG
  end

  def pb_icon(name, class_name: "h-5 w-5")
    paths = {
      "alert-circle" => '<circle cx="12" cy="12" r="10"></circle><line x1="12" x2="12" y1="8" y2="12"></line><line x1="12" x2="12.01" y1="16" y2="16"></line>',
      "alert-triangle" => '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"></path><path d="M12 9v4"></path><path d="M12 17h.01"></path>',
      "arrow-left" => '<path d="m12 19-7-7 7-7"></path><path d="M19 12H5"></path>',
      "arrow-right" => '<path d="M5 12h14"></path><path d="m12 5 7 7-7 7"></path>',
      "brain" => '<path d="M12 5a3 3 0 1 0-5.997.125 4 4 0 0 0-2.526 5.77 4 4 0 0 0 .556 6.588A4 4 0 1 0 12 18Z"></path><path d="M12 5a3 3 0 1 1 5.997.125 4 4 0 0 1 2.526 5.77 4 4 0 0 1-.556 6.588A4 4 0 1 1 12 18Z"></path><path d="M15 13a4.5 4.5 0 0 1-3-4 4.5 4.5 0 0 1-3 4"></path>',
      "calendar-days" => '<path d="M8 2v4"></path><path d="M16 2v4"></path><rect width="18" height="18" x="3" y="4" rx="2"></rect><path d="M3 10h18"></path><path d="M8 14h.01"></path><path d="M12 14h.01"></path><path d="M16 14h.01"></path><path d="M8 18h.01"></path><path d="M12 18h.01"></path><path d="M16 18h.01"></path>',
      "check" => '<path d="M20 6 9 17l-5-5"></path>',
      "check-circle" => '<path d="M21.801 10A10 10 0 1 1 17 3.335"></path><path d="m9 11 3 3L22 4"></path>',
      "clock" => '<circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline>',
      "eye" => '<path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"></path><circle cx="12" cy="12" r="3"></circle>',
      "file-search" => '<path d="M14 2v4a2 2 0 0 0 2 2h4"></path><path d="M4.268 21a2 2 0 0 0 1.727 1H18a2 2 0 0 0 2-2V7l-5-5H6a2 2 0 0 0-2 2v3"></path><path d="m9 18-1.5-1.5"></path><circle cx="5" cy="14" r="3"></circle>',
      "file-text" => '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"></path><path d="M14 2v4a2 2 0 0 0 2 2h4"></path><path d="M10 9H8"></path><path d="M16 13H8"></path><path d="M16 17H8"></path>',
      "folder-open" => '<path d="m6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2"></path>',
      "git-compare" => '<circle cx="18" cy="18" r="3"></circle><circle cx="6" cy="6" r="3"></circle><path d="M13 6h3a2 2 0 0 1 2 2v7"></path><path d="M11 18H8a2 2 0 0 1-2-2V9"></path>',
      "graduation-cap" => '<path d="M21.42 10.922a1 1 0 0 0-.019-1.838L12.83 5.18a2 2 0 0 0-1.66 0L2.6 9.08a1 1 0 0 0 0 1.832l8.57 3.908a2 2 0 0 0 1.66 0z"></path><path d="M22 10v6"></path><path d="M6 12.5V16a6 3 0 0 0 12 0v-3.5"></path>',
      "heart" => '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"></path>',
      "help-circle" => '<circle cx="12" cy="12" r="10"></circle><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"></path><path d="M12 17h.01"></path>',
      "list-checks" => '<path d="m3 17 2 2 4-4"></path><path d="m3 7 2 2 4-4"></path><path d="M13 6h8"></path><path d="M13 12h8"></path><path d="M13 18h8"></path>',
      "lock" => '<rect width="18" height="11" x="3" y="11" rx="2" ry="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path>',
      "mail" => '<rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path>',
      "menu" => '<line x1="4" x2="20" y1="12" y2="12"></line><line x1="4" x2="20" y1="6" y2="6"></line><line x1="4" x2="20" y1="18" y2="18"></line>',
      "message-square" => '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path>',
      "pencil" => '<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"></path><path d="m15 5 4 4"></path>',
      "plus" => '<path d="M5 12h14"></path><path d="M12 5v14"></path>',
      "play" => '<polygon points="6 3 20 12 6 21 6 3"></polygon>',
      "search" => '<circle cx="11" cy="11" r="8"></circle><path d="m21 21-4.3-4.3"></path>',
      "send" => '<path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"></path><path d="m21.854 2.147-10.94 10.939"></path>',
      "share-2" => '<circle cx="18" cy="5" r="3"></circle><circle cx="6" cy="12" r="3"></circle><circle cx="18" cy="19" r="3"></circle><line x1="8.59" x2="15.42" y1="13.51" y2="17.49"></line><line x1="15.41" x2="8.59" y1="6.51" y2="10.49"></line>',
      "shield" => '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"></path>',
      "sparkles" => '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"></path><path d="M20 3v4"></path><path d="M22 5h-4"></path><path d="M4 17v2"></path><path d="M5 18H3"></path>',
      "stethoscope" => '<path d="M11 2v2"></path><path d="M5 2v2"></path><path d="M5 3H4a2 2 0 0 0-2 2v4a6 6 0 0 0 12 0V5a2 2 0 0 0-2-2h-1"></path><path d="M8 15a6 6 0 0 0 12 0v-3"></path><circle cx="20" cy="10" r="2"></circle>',
      "trending-up" => '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"></polyline><polyline points="16 7 22 7 22 13"></polyline>',
      "upload" => '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="17 8 12 3 7 8"></polyline><line x1="12" x2="12" y1="3" y2="15"></line>',
      "user-check" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><polyline points="16 11 18 13 22 9"></polyline>',
      "user-circle" => '<circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="10" r="3"></circle><path d="M7 20.662V19a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v1.662"></path>',
      "users" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M22 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path>',
      "x" => '<path d="M18 6 6 18"></path><path d="m6 6 12 12"></path>'
    }

    icon = paths.fetch(name.to_s.tr("_", "-"))
    class_attr = ERB::Util.html_escape(class_name)

    %(<svg xmlns="http://www.w3.org/2000/svg" class="#{class_attr}" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">#{icon}</svg>).html_safe
  end
end
