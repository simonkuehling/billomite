class HomeController < ApplicationController
  layout 'standard'

  def help
    render :partial => 'help'
  end
  
  def index
  
  end
  
  def schritt2   
    # mite-Kunden auswählen
    # Auswahl: 
    #     Angemeldeter benutzer
    #     nicht abgeschlossen
    #     gruppiert nach Kunde
    
    if (params[:mite_id].empty? || params[:mite_key].empty? || params[:billomat_id].empty? || params[:billomat_key].empty?)
      flash[:error] = "Bitte alle Felder ausfüllen!"
      render :partial => 'error'
      return
    end 

    session['billomat_id'] = params[:billomat_id]
    session['billomat_key'] = params[:billomat_key]
    
    # mite API Konfiguration   
    Mite.account = params[:mite_id]
    Mite.key = params[:mite_key]
 
    # billomat API Konfiguration
    url = session['billomat_id'] + '.billomat.net'
    http = Net::HTTP::new(url, 80)
    path = '/api/users/myself'
    
    headers = { 'Content-Type'     => 'application/xml',
                'X-BillomatApiKey' => session['billomat_key'] }

    resp, xml_data = http.get(path, headers)
       
    # mite Verbindung prüfen
    if !(Mite.validate)
      flash[:error] = "Verbindung zu <i>mite</i> fehlgeschlagen - sind deine Daten korrekt?"
      render :partial => 'error'
      return
    end
    
    if (resp.code.to_i != 200)
      flash[:error] = "Verbindung zu <i>billomat</i> fehlgeschlagen - sind deine Daten korrekt?"
      render :partial => 'error'
      return
    end
    
    # mite Kunden suchen
    user = Mite::Myself.find
    aktive_projekte = Mite::Project.all
    kunden_akt = aktive_projekte.group_by {|projekt| projekt.customer_id }
    
    kunden = {}
    kunden_akt.each do |k|
      if k[0]
        kunde = Mite::Customer.find(k[0])
        kunden[k[0]] = kunde.name
      else
        kunden['nil'] = "[Keinem Kunden zugeordnet]"
      end
    end
    
    render :partial => 'schritt2', :object => kunden
  end
  
  def schritt3
    # Zeiteinträge listen zum auswählen
    akt_projekte = Mite::Project.all
    zeiten = []
    akt_projekte.each do |projekt|
      z = Mite::TimeEntry.all(:params => { :user_id     => Mite::Myself.find.id,
                                           :locked      => false,
                                           :project_id  => projekt.id,
                                           :customer_id => params[:id] })
      z.each do |x|
        if x.service_id
          zeiten << x
        end
      end                                              
    end
    session['zeiten'] = zeiten
    render :partial => 'schritt3', :object => zeiten
  end
  
  def schritt4
    # Fehler wenn kein Zeiteintrag ausgewählt
    if !(params[:zeiten])
      flash[:error] = "Es wurden keine Zeiteinträge ausgewählt."
      render :partial => 'error'
      return
    end
  
    # billomat-Kunden auflisten
    session['zeiten_auswahl'] = params[:zeiten]
    
    url = session['billomat_id'] + '.billomat.net'
    http = Net::HTTP::new(url, 80)
    path = '/api/clients'
    
    headers = { 'Content-Type'     => 'application/xml',
                'X-BillomatApiKey' => session['billomat_key'] }

    resp, xml_data = http.get(path, headers)
    data = XmlSimple.xml_in(xml_data)

    billomat_kunden = {}
    data['client'].each do |client|
      if client['name'].to_s == ''
        billomat_kunden[client['id'][0]['content'].to_s] = client['first_name'].to_s + " " + client['last_name'].to_s
      else
        billomat_kunden[client['id'][0]['content'].to_s] = client['name'].to_s
      end
    end
    
    render :partial => 'schritt4', :object => billomat_kunden
  end
  
  def schritt5
    # Rechnungspositionen generieren, dann Fertigstellen
    session['billomat_client'] = params[:id]
    zeiten_alle = session['zeiten']
    zeiten_auswahl = session['zeiten_auswahl']
    
    # Abgewählte Zeiteinträge entfernen
    zeiten = []
    zeiten_alle.each do |z|
      zeiten << z if zeiten_auswahl.include?(z.id.to_s)
    end
    
    # Rechnungspositionen zusammenstellen
    # Nach Projekt gruppieren
    positionen = []
    zeiten = zeiten.group_by {|entry| entry.project_id }

    zeiten.each do |f|
      titel = Mite::Project.find(f[0]).name
        
      # Nach Service gruppieren
      s = f[1].group_by {|entry| entry.service_id }
      s.each do |s,z|
        kilometer = 0
        minuten = 0
        service_name = Mite::Service.find(s).name
        hourly_rate = Mite::Service.find(s).hourly_rate
        bemerkung = ""
        bemerkung_km = ""    
      
        z.each do |t|      
          minuten += t.minutes
          
          # Datum einlesen
          d = t.date_at
          
          # Kilometer in Bemerkung finden, Bemerkung zusammenstellen
          km = /\(.*\).*\+(\d+)km/
          kmtr = km.match(t.note)
          if kmtr != nil then 
            kilometer += kmtr[1].to_i
            bemerkung_km = "(" + d.strftime('%d.%m.%Y') + ", " + kmtr[1].to_s + "km)\n" + bemerkung_km
          end
          
          # Zeitspanne in Bemerkung finden, Bemerkung zusammenstellen
          r = /\((.*)\)/
          vonbis = r.match(t.note) ? r.match(t.note)[1] : "..."
          bemerkung = "(" + d.strftime('%d.%m.%Y') + ", " + vonbis + ")\n" + bemerkung
        end
        
        stunden = '%.2f' % (minuten.to_f / 60)
        positionen << { 'anzahl'       => stunden.to_s,
                        'preis'        => '%.2f' % (hourly_rate.to_f / 100),
                        'einheit'      => "Stunden",
                        'titel'        => service_name.to_s,
                        'beschreibung' => titel.to_s + "\n" + bemerkung }
            
        # Fahrtkosten-Position zusammenstellen
        if kilometer != 0 then
          positionen << { 'anzahl'       => kilometer.to_s,
                          'preis'        => "0.30",
                          'einheit'      => "Kilometer",
                          'titel'        => "[L-6] Fahrtkosten PKW",
                          'beschreibung' => titel.to_s + "\n" + bemerkung_km }
        end
      end
    end    

    rechnung = { 'kunde'      => session["billomat_client"],
                 'kundenname' => params[:name],
                 'positionen' => positionen }
    session['rechnung'] = rechnung
    
    render :partial => 'schritt5', :object => rechnung
  end
  
  def schritt6
    # Rechnung erstellen - fertig.
    client_id = session['rechnung']['kunde']
    positionen = session['rechnung']['positionen']
  
    invoice = { 'client_id' => [ client_id.to_s ],
                'date'      => [ Date.today.to_s ] }
    
    item_array = []            
    positionen.each do |p|
      item_array << { 'unit'        => [ p['einheit'] ],
                      'unit_price'  => [ p['preis'] ],
                      'quantity'    => [ p['anzahl'] ],
                      'title'       => [ p['titel'] ],
                      'description' => [ p['beschreibung'] ] }
    end

    invoice['invoice-items'] = { 'invoice-item' => item_array }
    invoice_xml = XmlSimple.xml_out(invoice, {'RootName' => 'invoice'})

    # Rechnung anlegen
    # Rechnung neu anlegen
    url = session['billomat_id'] + '.billomat.net'
    http = Net::HTTP::new(url, 80)
    path = '/api/invoices'

    headers = { 'Content-Type'     => 'application/xml',
                'X-BillomatApiKey' => session['billomat_key'] }

    resp, data = http.post(path, invoice_xml, headers)
    xml_data = XmlSimple.xml_in(data)

    results = {}
    results['code'] = resp.code
    results['message'] = resp.message
    if ((resp.code.to_i >= 400) && (resp.code.to_i < 600 ))
      results['error'] = xml_data['error']
    else
      results['url'] = "http://" + url + "/portal/invoices/show/entityId/" + xml_data['id'][0]['content']
    end

    render :partial => 'schritt6', :object => results
  end
  
  def schritt7
    # In Rechnung gestellte Zeiteinträge in mite als abgeschlossen markieren
    
    session['zeiten_auswahl'].each do |id|
      time = Mite::TimeEntry.find(id)
      time.locked = true
      time.save
    end
    
    render :partial => 'schritt7'
  end
end
