import bpy
import os

# Variables for export path and base file name
export_path = "C:\Modding\MO2\DATA\mods\Experiments\meshes\debris"  # Replace with your desired export directory
base_file_name = "exported_object"  # Replace with your desired base file name

# Ensure the export path exists
if not os.path.exists(export_path):
    os.makedirs(export_path)

# Loop through all selected objects
selected_objects = bpy.context.selected_objects
for index, obj in enumerate(selected_objects):
    # Deselect all objects
    bpy.ops.object.select_all(action='DESELECT')
    
    # Select the current object
    obj.select_set(True)
    
    # Set the active object
    bpy.context.view_layer.objects.active = obj
    
    # Construct the file name
    file_name = f"{base_file_name}__chunk_{index}.nif"  # Assuming .nif is the desired extension
    file_path = os.path.join(export_path, file_name)
    
    # Export the object
    bpy.ops.export_scene.mw(filepath=file_path, use_selection=True, export_animations=False, extract_keyframe_data=False)

print("Export completed!")