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

	SANDBOX(1, "sb", "Sandbox environment", new String[] {"sandbox"}),
	CI(2, "ci", "Continuous integration environment", new String[] {}),
	QA(3, "qa", "Quality assurance environment", new String[] {}),
	STAGING(4, "stg", "Staging environment", new String[] {"staging", "stage"}),
	PRODUCTION(5, "prod", "Production environment", new String[] {"production"});
	
	private String id;
	private String description;
	private int order;
	private String[] aliases;

	private Landscape(int order, String id, String description, String[] aliases) {
		this.order = order;
		this.id = id;
		this.description = description;
		this.aliases = aliases;
	}
	
	public static Set<Landscape> getIds() {
		Set<Landscape> ids = new TreeSet<Landscape>(new Comparator<Landscape>() {
			@Override public int compare(Landscape o1, Landscape o2) {
				return o1.getOrder() - o2.getOrder();
			}});
		ids.addAll(Arrays.asList(Landscape.values()));
		
		return ids;
	}
	
	/**
	 * If provided landscape name matches (excluding case) the id of a Landscape enum value or one of its aliases, then return the landscape id.
	 * Otherwise return the provided landscape unchanged.
	 * This will correct certain anticipated guesses at some of the standard landscape names, and enforce lowercasing.
	 * @param possibleAlias
	 * @return
	 */
	public static String idFromAlias(String possibleAlias) {
		if(possibleAlias == null || possibleAlias.isBlank()) {
			return possibleAlias;
		}
		Landscape landscape = fromAlias(possibleAlias);
		if(landscape == null) {
			return possibleAlias;
		}
		return landscape.getId();
	}
	
	public static Landscape fromAlias(String possibleAlias) {
		if(possibleAlias == null || possibleAlias.isBlank()) {
			return null;
		}
		for(Landscape landscape : Landscape.values()) {
			if(landscape.name().equalsIgnoreCase(possibleAlias)) {
				return landscape;
			}
			if(landscape.getId().equalsIgnoreCase(possibleAlias)) {
				return landscape;
			}
			else {
				for(String alias : landscape.getAliases()) {
					if(alias.equalsIgnoreCase(possibleAlias)) {
						return landscape;
					}
				}
			}
		}
		return null;		
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
	public String[] getAliases() {
		return aliases;
	}
}