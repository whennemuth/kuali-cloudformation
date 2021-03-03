package org.bu.jenkins.active_choices.model;

import java.util.Arrays;
import java.util.Comparator;
import java.util.Set;
import java.util.TreeSet;

/**
 * There are 5 basic landscapes (environments) that have traditionally been used for kuali deployments.
 * Therefore, they are enumerated here.
 * @author wrh
 *
 */
public enum Landscape {

	SANDBOX(1, "sb", "Sandbox environment"),
	CI(2, "ci", "Continuous integration environment"),
	QA(3, "qa", "Quality assurance environment"),
	STAGING(4, "stg", "Staging environment"),
	PRODUCTION(5, "prod", "Production environment");
	
	private String id;
	private String description;
	private int order;

	private Landscape(int order, String id, String description) {
		this.order = order;
		this.id = id;
		this.description = description;
	}
	
	public static Set<Landscape> getIds() {
		Set<Landscape> ids = new TreeSet<Landscape>(new Comparator<Landscape>() {
			@Override public int compare(Landscape o1, Landscape o2) {
				return o1.getOrder() - o2.getOrder();
			}});
		ids.addAll(Arrays.asList(Landscape.values()));
		
		return ids;
	}

	public String getId() {
		return id;
	}
	public int getOrder() {
		return order;
	}
	public String getDescription() {
		return description;
	}

}
