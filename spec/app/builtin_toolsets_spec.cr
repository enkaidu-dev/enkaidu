require "../spec_helper"

KNOWN_TOOLSETS = ["FileManagement", "TextEditing", "DateAndTime", "ImageEditing", "ShellAccess"]

Spectator.describe Tools do
  describe "has known toolset" do
    it "that is registered" do
      {% for name, ix in KNOWN_TOOLSETS %}
        expect(Tools[{{name}}]?).not_to be(nil)
      {% end %}
    end
  end

  describe "has registered toolset" do
    it "that is tested" do
      # Detect and fail any toolsets not in our list
      Tools.each_toolset do |toolset|
        expect(KNOWN_TOOLSETS).to have(toolset.name)
      end
    end
  end
end
