package org.bu.jenkins.mvc.model;

import java.util.HashMap;
import java.util.Map;
import java.util.Map.Entry;

public abstract class AbstractAwsResource {

	protected String arn;
	protected String name;
	protected Map<String, String> tags = new HashMap<String, String>();

	public AbstractAwsResource() {
		super();
	}
	public AbstractAwsResource(String arn) {
		super();
		this.arn = arn;
	}
	public AbstractAwsResource(String arn, String landscape, String baseline) {
		super();
		this.arn = arn;
		this.tags.put("Landscape", landscape);
		this.tags.put("Baseline", baseline);

	}
	public AbstractAwsResource(String arn, Map<String, String> tags) {
		this.arn = arn;
		this.tags.putAll(tags);
	}
	public String getArn() {
		return arn;
	}
	public AbstractAwsResource setArn(String arn) {
		this.arn = arn;
		return this;
	}
	public String getName() {
		if(this.name == null) {
			
		}
		return this.name;
	}
	public AbstractAwsResource setName(String name) {
		this.name = name;
		return this;
	}
	public String getBaseline() {
		return getTagValue("Baseline");
	}
	public AbstractAwsResource setBaseline(String baseline) {
		return putTag("Baseline", baseline);
	}
	public Map<String, String> getTags() {
		return tags;
	}
	public String getLandscape() {
		return getTagValue("Landscape");
	}
	public AbstractAwsResource setLandscape(String landscape) {
		return putTag("Landscape", landscape);
	}
	public AbstractAwsResource setTags(Map<String, String> tags) {
		this.tags.putAll(tags);
		return this;
	}
	public AbstractAwsResource putTag(String key, String value) {
		this.tags.put(key, value);
		return this;
	}
	protected String getTagValue(String key) {
		for(Entry<String, String> e : tags.entrySet()) {
			if(e.getKey().equalsIgnoreCase(key)) return e.getValue();
		}
		return null;
	}

}
