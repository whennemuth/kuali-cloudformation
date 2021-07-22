package org.bu.jenkins.job;

import java.net.URLDecoder;
import java.nio.charset.Charset;
import java.util.HashMap;
import java.util.Map;

/**
 * Convenience bean to consolidate parameters consumed by getRenderedParameter
 * 
 * @author wrh
 *
 */
public class JobParameterConfiguration {
	private String parameterName;
	private String invalidStateMessage;
	private Map<String, String> parameterMap = new HashMap<String, String>();
	private boolean activeChoices;
	private boolean html = true;
	private boolean renderName = true;
	private boolean renderDescription = false;
	private boolean developmentMode;
	
	private JobParameterConfiguration() { super(); }
	
	public String getParameterName() {
		if(parameterName == null) return null;
		return parameterName;
	}
	public void setParameterName(String parameterName) {
		this.parameterName = parameterName;
	}
	public Map<String, String> getParameterMap() {
		return parameterMap;
	}
	public JobParameterConfiguration setParameterMap(Map<String, String> parameterMap) {
		for(String key : parameterMap.keySet()) {
			String value = parameterMap.get(key);
			if(value != null) {
				value = URLDecoder.decode(String.valueOf(value), Charset.defaultCharset());
			}
			setParameterMapValue(key, value);
		}
		return this;
	}
	public JobParameterConfiguration setParameterMapValue(String parameterName, String parameterValue) {
		if(parameterValue != null) {
			parameterValue = URLDecoder.decode(String.valueOf(parameterValue), Charset.defaultCharset());
		}
		parameterMap.put(parameterName, parameterValue);
		return this;
	}
	/**
	 * Indicates if the parameter represents an actual active choices field and is not proxying for a hidden 
	 * active choices field (as fields rendered by AbstractJob). If true, the html field gets a name of "value"
	 * to allow it to be recognized by the active choices plugin as a field that it manages, where the actual
	 * name would be applied on the active choices field configuration within the job.
	 * 
	 * @return
	 */
	public boolean isActiveChoices() {
		return activeChoices;
	}
	public void setActiveChoices(boolean activeChoices) {
		this.activeChoices = activeChoices;
	}
	public boolean isHtml() {
		return html;
	}
	public JobParameterConfiguration setHtml(boolean html) {
		this.html = html;
		return this;
	}
	public boolean isRenderName() {
		if(activeChoices || html==false) {
			return false;
		}
		return renderName;
	}
	public JobParameterConfiguration setRenderName(boolean renderName) {
		this.renderName = renderName;
		return this;
	}
	public boolean isRenderDescription() {
		if(html == false) {
			return false;
		}
		return renderDescription;
	}
	public JobParameterConfiguration setRenderDescription(boolean renderDescription) {
		this.renderDescription = renderDescription;
		return this;
	}
	public boolean isDevelopmentMode() {
		return developmentMode;
	}
	public JobParameterConfiguration setDevelopmentMode(boolean developmentMode) {
		this.developmentMode = developmentMode;
		return this;
	}
	public String getInvalidStateMessage() {
		return invalidStateMessage;
	}
	public boolean hasInvalidStateMessage() {
		return invalidStateMessage != null;
	}
	public JobParameterConfiguration setInvalidStateMessage(String invalidStateMessage) {
		this.invalidStateMessage = invalidStateMessage;
		return this;
	}
	public static JobParameterConfiguration getInstance() {
		return new JobParameterConfiguration();
	}
	
	public static JobParameterConfiguration getNestedFieldInstance(String parameterName) {
		JobParameterConfiguration config = new JobParameterConfiguration();
		config.parameterName = parameterName;
		return config;			
	}
	public static JobParameterConfiguration getActiveChoicesFieldInstance(String parameterName) {
		JobParameterConfiguration config = new JobParameterConfiguration();
		config.parameterName = parameterName;
		config.activeChoices = true;
		return config;
	}

}