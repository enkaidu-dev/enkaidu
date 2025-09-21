module Enkaidu::Server
  enum Work
    # When an event has been posted
    RenderEventPosted
    # When a request has been completed
    RequestHandled
  end
end
