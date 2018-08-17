package edu.bu.ist.apps.aws.task;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * This class masks values with asterisk characters to obfuscate sensitive info like passwords, etc.
 * A value is masked if a lookup in a provided json object matches its key in either a "full" of "logs" array of field names.
 * If a match is found in the full array, both output and logging output are masked.
 * If a match is found in the logs array, just the logging output is masked.
 * 
 * @author wrh
 *
 */
public class BasicOutputMask implements OutputMask {

	private JSONObject parameters;	
	private static final String MASK_CHAR = "*";
	
	public BasicOutputMask(String json) {
		parameters = new JSONObject(json);
	}
	
	@Override
	public String getLogOutput(String key, Object value) {
		return getMaskForField( key, getMaskForField(key, value, "logs"), "full");
	}

	@Override
	public String getOutput(String key, Object value) {
		return getMaskForField(key, value, "full");
	}

	private String getMaskForField(String key, Object value, String type) {
		
		if(key == null || value == null)
			return null;
		if(String.valueOf(value).trim().isEmpty())
			return null;
		
		if(maskAllFields(type)) {
			return getMask(((String) value).length());
		}
		
		StringBuilder mask = new StringBuilder((String) value);	
		
		JSONArray fieldsToMask = getFieldsToMask(type);		
		if(fieldsToMask != null) {
			fieldsToMask.forEach( (field) -> {
				if(key.equalsIgnoreCase((String) field)) {
					mask.replace(0, mask.length(), getMask(mask.length()));
					return;
				}
			});
		}
		
		return mask.toString();		
	}
	
	private JSONArray getFieldsToMask(String type) {
		if(parameters.has("fieldsToMask") && parameters.getJSONObject("fieldsToMask").has(type)) {
			return parameters.getJSONObject("fieldsToMask").getJSONArray(type);
		}
		return null;
	}
	
	private boolean maskAllFields(String type) {
		JSONArray fieldsToMask = getFieldsToMask(type);
		if(fieldsToMask != null && fieldsToMask.length() == 1) {
			if(OutputMask.ALL_FIELDS.equalsIgnoreCase(fieldsToMask.getString(0))) {
				return true;
			}
		}
		return false;
	}
	
	private String getMask(int length) {
		StringBuilder s = new StringBuilder();
		for(int i=1; i<=length; i++) {
			s.append(MASK_CHAR);
		}
		return s.toString();
	}
}
